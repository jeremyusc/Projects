// ============================================================
// Regfile Map: 
//   r1 = i (outer loop counter)
//   r2 = j (inner loop counter)
//   r3 = N - 1 = 9 (max index for an array of 10 elements)
//   r4 = limit = N - 1 - i (dynamic limit for the inner loop)
//   r5 = A[j] (current element)
//   r6 = A[j+1] (next element)
//   r7 = j * 4 (memory byte offset)
//   r9 = cmp (comparison result flag)
//
// Custom Instruction Format:
//   BEQ : op=C, rs=r0addr, rt=r1addr, imm=offset
//   inst[31:28]=C, inst[27:24]=rs, inst[23:20]=rt, inst[15:0]=imm
//
// Optimization Details (Pipeline Hazard Handling):
//   OUTER_CHECK: Originally `SLT + 4 NOPs + BNEZ` = 6 instructions.
//                Now replaced with `BEQ r1, r3, DONE` + `BEQZ r0, INNER_SETUP` = 2 instructions (No NOPs needed!).
//   INNER_CHECK: Originally `SLT + 4 NOPs + BNEZ` = 6 instructions.
//                Now replaced with `BEQ r2, r4, OUTER_INC` = 1 instruction.
//
// Pipeline Note: 
//   BEQ reads registers in the ID (Instruction Decode) stage, just like BEQZ/BNEZ.
//   Therefore, if you write to a register, you still need 4 NOPs before a BEQ can read the updated value due to data hazards.
//   However, BEQ itself performs the comparison and branching simultaneously without needing extra NOPs.

// --- INITIALIZATION ---
// Setup the array bounds and outer loop counter.
// 0x000: ADDI r3=9          // r3 = 9 (Array length N=10, so N-1=9)
// 0x001~004: NOP x4         // Wait for r3 to be written back to Regfile
// 0x005: ADDI r1=0          // r1 (i) = 0
// 0x006~009: NOP x4         // Wait for r1 to be written back

// --- OUTER LOOP CONDITION=---
// Checks if the outer loop has finished its runs.
// 0x00A: BEQ  r1,r3 → DONE  // If i == N-1, sorting is fully complete. Jump to DONE.
// 0x00B: BEQZ r0,   → INNER_SETUP // Unconditional jump to setup the inner loop (r0 is always 0).

// --- INNER LOOP SETUP=---
// Prepares variables for the inner traversal.
// 0x00C: ADDI r2=0          // r2 (j) = 0. Reset inner loop counter.
// 0x00D: SUB  r4=r3-r1      // limit (r4) = (N-1) - i. The largest elements bubble to the end, so we check fewer elements each pass.
// 0x00E~011: NOP x4         // Wait for r2 and r4 to be written back

// --- INNER LOOP CONDITION (INNER_CHECK) ---
// Checks if the inner loop has reached the unsorted boundary.
// 0x012: BEQ  r2,r4 → OUTER_INC // If j == limit, the current pass is done. Jump to increment outer loop.
// 0x013: SLL  r7=r2<<2      // Calculate memory byte offset: r7 = j * 4 (since each word is 4 bytes).
// 0x014~017: NOP x4         // Wait for r7 to be written back
// 0x018: LW   r5=mem[r7]    // Load A[j] into r5
// 0x019: LW   r6=mem[r7+4]  // Load adjacent element A[j+1] into r6
// 0x01A~01D: NOP x4         // Wait for memory loads (r5, r6) to complete and write back

// --- COMPARE ---
// Evaluates if the adjacent elements are out of order.
// 0x01E: SLT  r9=(r6<r5)    // Compare: Set r9=1 if A[j+1] < A[j], else r9=0.
// 0x01F~022: NOP x4         // Wait for comparison result (r9) to be written back
// 0x023: BEQZ r9, → J_INC   // If r9 == 0 (A[j] <= A[j+1]), they are in the correct order. Skip swap and jump to J_INC.

// --- SWAP ---
// Swaps the elements in memory if they were out of order.
// 0x024: SW   r6, 0(r7)     // Store A[j+1] value into A[j]'s memory location
// 0x025: SW   r5, 4(r7)     // Store A[j] value into A[j+1]'s memory location

// --- INNER LOOP (J) ---
// Advances the inner loop counter.
// 0x026: ADDI r2=r2+1       // j++
// 0x027~02A: NOP x4         // Wait for r2 to be written back
// 0x02B: BEQZ r0, → INNER_CHECK // Unconditional jump back to evaluate the inner loop condition

// --- OUTER LOOP (OUTER_INC) ---
// Advances the outer loop counter once a full inner pass is complete.
// 0x02C: ADDI r1=r1+1       // i++
                             // (No NOPs needed here because the next BEQ reads r1 in the ID stage, and the jump to OUTER_CHECK adds enough delay/bubbles naturally in this layout, or the branch target simply evaluates it next time around depending on exact pipeline specs).
// 0x02D: BEQZ r0, → OUTER_CHECK // Unconditional jump back to evaluate the outer loop condition
// ============================================================
// Branch Immediate Offsets Calculation
// ============================================================
//   0x00A BEQ:  ifid_pc = 0x00A * 4 = 40.   Target = 0x02E * 4 = 184.  imm = 184 - 40 = 144  (0x90)
//   0x00B BEQZ: ifid_pc = 0x00B * 4 = 44.   Target = 0x00C * 4 = 48.   imm = 4
//   0x012 BEQ:  ifid_pc = 0x012 * 4 = 72.   Target = 0x02C * 4 = 176.  imm = 176 - 72 = 104  (0x68)
//   0x023 BEQZ: ifid_pc = 0x023 * 4 = 140.  Target = 0x026 * 4 = 152.  imm = 12              (0x0C)
//   0x02B BEQZ: ifid_pc = 0x02B * 4 = 172.  Target = 0x012 * 4 = 72.   imm = 72 - 172 = -100 (0xFF9C)
//   0x02D BEQZ: ifid_pc = 0x02D * 4 = 180.  Target = 0x00A * 4 = 40.   imm = 40 - 180 = -140 (0xFF74)

`timescale 1ns / 1ps
module tb_4t_bubble_sort;
logic clk, rst;
logic        intf_wen_imem;
logic  [8:0] intf_addr_imem;
logic [31:0] intf_data_imem;
logic        web;
logic [63:0] dinb;
logic  [7:0] addrb;

pipeline_top dut(
    .clk(clk), .rst(rst),
    .intf_wen_imem(intf_wen_imem),
    .intf_addr_imem(intf_addr_imem),
    .intf_data_imem(intf_data_imem),
    .web(web), .dinb(dinb), .addrb(addrb)
);

always #5 clk = ~clk;

task automatic load_imem(input logic [8:0] addr, input logic [31:0] data);
    @(negedge clk); intf_wen_imem=1; intf_addr_imem=addr; intf_data_imem=data;
    @(negedge clk); intf_wen_imem=0;
endtask

task automatic load_dmem(input logic [7:0] addr, input logic [63:0] data);
    @(negedge clk); web=1; addrb=addr; dinb=data;
    @(negedge clk); web=0;
endtask



initial begin
    clk=0; rst=1;
    intf_wen_imem=0; web=0; dinb=0; addrb=0;
    @(negedge clk);

//------------------------------LOAD_DATA-------------------------------------------------
    load_dmem(8'h00, 64'd323);
    load_dmem(8'h04, 64'd123);
    load_dmem(8'h08, 64'hFFFFFFFFFFFFFE39); // -455
    load_dmem(8'h0C, 64'd2);
    load_dmem(8'h10, 64'd98);
    load_dmem(8'h14, 64'd125);
    load_dmem(8'h18, 64'd10);
    load_dmem(8'h1C, 64'd65);
    load_dmem(8'h20, 64'hFFFFFFFFFFFFFFC8); // -56
    load_dmem(8'h24, 64'd0);

//-------------------------INST_MEM/-----------------------------

    // 0x000: ADDI r3=9  (op=3,rs=0,WReg=3,imm=9)
    load_imem(9'h000, 32'h30030009);
    // 0x001: ADDI r1=0  (op=3,rs=0,WReg=1,imm=0)
    load_imem(9'h001, 32'h30010000);

    // ── OUTER_CHECK (Word Index: 2) ──
    // 0x002: BEQ r1,r3 → DONE (Target: 18) | Offset = (18-2)*4 = 64 = 0x0040
    load_imem(9'h002, 32'hC1300040); 
    // 0x003: BEQZ r0, +4 → INNER_SETUP (0x004)
    load_imem(9'h003, 32'h80000004);

    // ── INNER_SETUP (Word Index: 4) ──
    // 0x004: ADDI r2=0 
    load_imem(9'h004, 32'h30020000);
    // 0x005: SUB r4=r3-r1
    load_imem(9'h005, 32'h23140000);

    // ── INNER_CHECK (Word Index: 6) ──
    // 0x006: BEQ r2,r4 → OUTER_INC (Target: 16) | Offset = (16-6)*4 = 40 = 0x0028
    load_imem(9'h006, 32'hC2400028);
    // 0x007: SLL r7=r2<<2 
    load_imem(9'h007, 32'hB2070002);
    // 0x008: LW r5=mem[r7] 
    load_imem(9'h008, 32'h67050000);
    // 0x009: LW r6=mem[r7+4] 
    load_imem(9'h009, 32'h67060004);

    // ── COMPARE (Word Index: 10) ──
    // 0x00A: SLT r9=(r6<r5) 
    load_imem(9'h00A, 32'hA6590000);
    // 0x00B: BEQZ r9, +12 → J_INC (Target: 14) | Offset = (14-11)*4 = 12 = 0x000C
    load_imem(9'h00B, 32'h8900000C);

    // ── SWAP (Word Index: 12) ──
    // 0x00C: SW r6, 0(r7) 
    load_imem(9'h00C, 32'h77600000);
    // 0x00D: SW r5, 4(r7) 
    load_imem(9'h00D, 32'h77500004);

    // ── J_INC (Word Index: 14) ──
    // 0x00E: ADDI r2=r2+1  
    load_imem(9'h00E, 32'h32020001);
    // 0x00F: BEQZ r0, → INNER_CHECK (Target: 6) | Offset = (6-15)*4 = -36 = 0xFFDC
    load_imem(9'h00F, 32'h8000FFDC);

    // ── OUTER_INC (Word Index: 16) ──
    // 0x010: ADDI r1=r1+1 
    load_imem(9'h010, 32'h31010001);
    // 0x011: BEQZ r0, → OUTER_CHECK (Target: 2) | Offset = (2-17)*4 = -60 = 0xFFC4
    load_imem(9'h011, 32'h8000FFC4);

    // ── DONE (Word Index: 18) ──
    load_imem(9'h012, 32'h00000000); // 結束或無窮迴圈

    // ── 安全隔離區 (讓 Thread 1, 2, 3 待在這裡) ──
    // 讓它們在位址 0x080 的地方執行 BEQZ r0, 0 (無限原地跳躍)
    load_imem(9'h020, 32'h80000000); // 9'h020 = 位址 0x080


    @(negedge clk);
    



    rst = 0; // 放開 Reset！
	@(negedge clk);
	dut.u_if.pc_reg[1] = 11'h080;
    dut.u_if.pc_reg[2] = 11'h080;
    dut.u_if.pc_reg[3] = 11'h080;
    /////////////Debug/////////
    repeat(100) begin
        @(posedge clk);
        // 只印出 Thread 0 的狀態來觀察，避免畫面太亂
        if (dut.id_thread_id == 2'b00) begin
            $display("[Thread 0] PC=%0d | wb_wen=%b wb_waddr=%0d wb_data=%0d",
                     dut.u_if.pc_reg[0], dut.wb_wen, dut.wb_waddr, dut.wb_data);
        end
    end

    ///////////////////////////////////////////////
    // 緊湊版不需要那麼多 Clock，大概 2000 個週期就能排完！
    repeat(4000) @(posedge clk);

    $display("=== Bubble Sort Result (N=10) ===");
    $display("addr 0  = %0d (expect -455)", $signed(dut.u_mem.mem[0]));
    $display("addr 4  = %0d (expect  -56)", $signed(dut.u_mem.mem[4]));
    $display("addr 8  = %0d (expect    0)", $signed(dut.u_mem.mem[8]));
    $display("addr 12 = %0d (expect    2)", $signed(dut.u_mem.mem[12]));
    $display("addr 16 = %0d (expect   10)", $signed(dut.u_mem.mem[16]));
    $display("addr 20 = %0d (expect   65)", $signed(dut.u_mem.mem[20]));
    $display("addr 24 = %0d (expect   98)", $signed(dut.u_mem.mem[24]));
    $display("addr 28 = %0d (expect  123)", $signed(dut.u_mem.mem[28]));
    $display("addr 32 = %0d (expect  125)", $signed(dut.u_mem.mem[32]));
    $display("addr 36 = %0d (expect  323)", $signed(dut.u_mem.mem[36]));
    $display("=================================");
    $finish;
end
endmodule