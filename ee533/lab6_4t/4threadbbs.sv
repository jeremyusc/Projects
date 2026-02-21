`timescale 1ns / 1ps
module tb_bubble_sort_4thread;
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

    // ── 資料區域規劃 ──
    // Thread 0: mem[0x00 ~ 0x24]   (addr 0~36)
    // Thread 1: mem[0x28 ~ 0x4C]   (addr 40~76)
    // Thread 2: mem[0x50 ~ 0x74]   (addr 80~116)
    // Thread 3: mem[0x78 ~ 0x9C]   (addr 120~156)

    // Thread 0 data
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

    // Thread 1 data (base offset = 0x28 = 40)
    load_dmem(8'h28, 64'd9);
    load_dmem(8'h2C, 64'd7);
    load_dmem(8'h30, 64'd5);
    load_dmem(8'h34, 64'd3);
    load_dmem(8'h38, 64'd1);
    load_dmem(8'h3C, 64'd8);
    load_dmem(8'h40, 64'd6);
    load_dmem(8'h44, 64'd4);
    load_dmem(8'h48, 64'd2);
    load_dmem(8'h4C, 64'd0);

    // Thread 2 data (base offset = 0x50 = 80)
    load_dmem(8'h50, 64'hFFFFFFFFFFFFFFFF); // -1
    load_dmem(8'h54, 64'hFFFFFFFFFFFFFFFE); // -2
    load_dmem(8'h58, 64'hFFFFFFFFFFFFFFFD); // -3
    load_dmem(8'h5C, 64'hFFFFFFFFFFFFFFFC); // -4
    load_dmem(8'h60, 64'hFFFFFFFFFFFFFFFB); // -5
    load_dmem(8'h64, 64'd100);
    load_dmem(8'h68, 64'd200);
    load_dmem(8'h6C, 64'd300);
    load_dmem(8'h70, 64'd400);
    load_dmem(8'h74, 64'd500);

    // Thread 3 data (base offset = 0x78 = 120)
    load_dmem(8'h78, 64'd50);
    load_dmem(8'h7C, 64'd40);
    load_dmem(8'h80, 64'd30);
    load_dmem(8'h84, 64'd20);
    load_dmem(8'h88, 64'd10);
    load_dmem(8'h8C, 64'd60);
    load_dmem(8'h90, 64'd70);
    load_dmem(8'h94, 64'd80);
    load_dmem(8'h98, 64'd90);
    load_dmem(8'h9C, 64'd100);

    // ── 指令區域規劃 ──
    // Thread 0: 從 imem[0x000] 開始，base addr = 0x00 (r8=0)
    // Thread 1: 從 imem[0x040] 開始，base addr = 0x28 (r8=40)
    // Thread 2: 從 imem[0x080] 開始，base addr = 0x50 (r8=80)
    // Thread 3: 從 imem[0x0C0] 開始，base addr = 0x78 (r8=120)
    //
    // 每個 thread 的程式相同，只有 r8 (base addr) 不同
    // LW/SW 改成 LW r5=mem[r7+r8], 但因為你的 ISA 只有 imm offset
    // 所以用 r7 = base + j*4 的方式，把 base 存在 r8，SLL 後 ADD

    // ── Thread 0 程式 (imem 0x000~0x01F, base=0) ──
    // r8 = base address = 0
// Thread 0 (offset 0x000, base=0)
load_imem(9'h000, 32'h30080000); // ADDI r8=0
load_imem(9'h001, 32'h30030009); // ADDI r3=9
load_imem(9'h002, 32'h30010000); // ADDI r1=0
load_imem(9'h003, 32'hC1300044); // BEQ r1,r3 → DONE  offset=0x44
load_imem(9'h004, 32'h80000004); // BEQZ r0 → INNER_SETUP
load_imem(9'h005, 32'h30020000); // ADDI r2=0
load_imem(9'h006, 32'h23140000); // SUB r4=r3-r1
load_imem(9'h007, 32'hC240002C); // BEQ r2,r4 → OUTER_INC offset=0x2C
load_imem(9'h008, 32'hB2070002); // SLL r7=r2<<2
load_imem(9'h009, 32'h17870000); // ADD r7=r7+r8
load_imem(9'h00A, 32'h67050000); // LW r5=mem[r7]
load_imem(9'h00B, 32'h67060004); // LW r6=mem[r7+4]
load_imem(9'h00C, 32'hA6590000); // SLT r9=(r6<r5)
load_imem(9'h00D, 32'h8900000C); // BEQZ r9 → J_INC offset=0xC
load_imem(9'h00E, 32'h77600000); // SW r6,0(r7)
load_imem(9'h00F, 32'h77500004); // SW r5,4(r7)
load_imem(9'h010, 32'h32020001); // ADDI r2=r2+1
load_imem(9'h011, 32'h8000FFD8); // BEQZ r0 → INNER_CHECK offset=0xFFD8
load_imem(9'h012, 32'h31010001); // ADDI r1=r1+1
load_imem(9'h013, 32'h8000FFC0); // BEQZ r0 → OUTER_CHECK offset=0xFFC0
load_imem(9'h014, 32'h00000000); // NOP

// Thread 1 (offset 0x100, base=40=0x28)
load_imem(9'h040, 32'h30080028); // ADDI r8=40
load_imem(9'h041, 32'h30030009);
load_imem(9'h042, 32'h30010000);
load_imem(9'h043, 32'hC1300044);
load_imem(9'h044, 32'h80000004);
load_imem(9'h045, 32'h30020000);
load_imem(9'h046, 32'h23140000);
load_imem(9'h047, 32'hC240002C);
load_imem(9'h048, 32'hB2070002);
load_imem(9'h049, 32'h17870000);
load_imem(9'h04A, 32'h67050000);
load_imem(9'h04B, 32'h67060004);
load_imem(9'h04C, 32'hA6590000);
load_imem(9'h04D, 32'h8900000C);
load_imem(9'h04E, 32'h77600000);
load_imem(9'h04F, 32'h77500004);
load_imem(9'h050, 32'h32020001);
load_imem(9'h051, 32'h8000FFD8);
load_imem(9'h052, 32'h31010001);
load_imem(9'h053, 32'h8000FFC0);
load_imem(9'h054, 32'h00000000);

// Thread 2 (offset 0x200, base=80=0x50)
load_imem(9'h080, 32'h30080050); // ADDI r8=80
load_imem(9'h081, 32'h30030009);
load_imem(9'h082, 32'h30010000);
load_imem(9'h083, 32'hC1300044);
load_imem(9'h084, 32'h80000004);
load_imem(9'h085, 32'h30020000);
load_imem(9'h086, 32'h23140000);
load_imem(9'h087, 32'hC240002C);
load_imem(9'h088, 32'hB2070002);
load_imem(9'h089, 32'h17870000);
load_imem(9'h08A, 32'h67050000);
load_imem(9'h08B, 32'h67060004);
load_imem(9'h08C, 32'hA6590000);
load_imem(9'h08D, 32'h8900000C);
load_imem(9'h08E, 32'h77600000);
load_imem(9'h08F, 32'h77500004);
load_imem(9'h090, 32'h32020001);
load_imem(9'h091, 32'h8000FFD8);
load_imem(9'h092, 32'h31010001);
load_imem(9'h093, 32'h8000FFC0);
load_imem(9'h094, 32'h00000000);

// Thread 3 (offset 0x300, base=120=0x78)
load_imem(9'h0C0, 32'h30080078); // ADDI r8=120
load_imem(9'h0C1, 32'h30030009);
load_imem(9'h0C2, 32'h30010000);
load_imem(9'h0C3, 32'hC1300044);
load_imem(9'h0C4, 32'h80000004);
load_imem(9'h0C5, 32'h30020000);
load_imem(9'h0C6, 32'h23140000);
load_imem(9'h0C7, 32'hC240002C);
load_imem(9'h0C8, 32'hB2070002);
load_imem(9'h0C9, 32'h17870000);
load_imem(9'h0CA, 32'h67050000);
load_imem(9'h0CB, 32'h67060004);
load_imem(9'h0CC, 32'hA6590000);
load_imem(9'h0CD, 32'h8900000C);
load_imem(9'h0CE, 32'h77600000);
load_imem(9'h0CF, 32'h77500004);
load_imem(9'h0D0, 32'h32020001);
load_imem(9'h0D1, 32'h8000FFD8);
load_imem(9'h0D2, 32'h31010001);
load_imem(9'h0D3, 32'h8000FFC0);
load_imem(9'h0D4, 32'h00000000);

    @(negedge clk);
    rst = 0;
    @(negedge clk);

    // 設定各 thread 的起始 PC
    dut.u_if.pc_reg[0] = 11'h000; // Thread 0 從 0x000
    dut.u_if.pc_reg[1] = 11'h100; // Thread 1 從 0x100 (imem word addr 0x040 = byte 0x100)
    dut.u_if.pc_reg[2] = 11'h200; // Thread 2 從 0x200
    dut.u_if.pc_reg[3] = 11'h300; // Thread 3 從 0x300

    repeat(40000) @(posedge clk);

    $display("=== Thread 0 Result (base=0x00) ===");
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

    $display("=== Thread 1 Result (base=0x28) ===");
    $display("addr 40 = %0d (expect 0)",  $signed(dut.u_mem.mem[40]));
    $display("addr 44 = %0d (expect 1)",  $signed(dut.u_mem.mem[44]));
    $display("addr 48 = %0d (expect 2)",  $signed(dut.u_mem.mem[48]));
    $display("addr 52 = %0d (expect 3)",  $signed(dut.u_mem.mem[52]));
    $display("addr 56 = %0d (expect 4)",  $signed(dut.u_mem.mem[56]));
    $display("addr 60 = %0d (expect 5)",  $signed(dut.u_mem.mem[60]));
    $display("addr 64 = %0d (expect 6)",  $signed(dut.u_mem.mem[64]));
    $display("addr 68 = %0d (expect 7)",  $signed(dut.u_mem.mem[68]));
    $display("addr 72 = %0d (expect 8)",  $signed(dut.u_mem.mem[72]));
    $display("addr 76 = %0d (expect 9)",  $signed(dut.u_mem.mem[76]));

    $display("=== Thread 2 Result (base=0x50) ===");
    $display("addr 80  = %0d (expect -5)",   $signed(dut.u_mem.mem[80]));
    $display("addr 84  = %0d (expect -4)",   $signed(dut.u_mem.mem[84]));
    $display("addr 88  = %0d (expect -3)",   $signed(dut.u_mem.mem[88]));
    $display("addr 92  = %0d (expect -2)",   $signed(dut.u_mem.mem[92]));
    $display("addr 96  = %0d (expect -1)",   $signed(dut.u_mem.mem[96]));
    $display("addr 100 = %0d (expect 100)",  $signed(dut.u_mem.mem[100]));
    $display("addr 104 = %0d (expect 200)",  $signed(dut.u_mem.mem[104]));
    $display("addr 108 = %0d (expect 300)",  $signed(dut.u_mem.mem[108]));
    $display("addr 112 = %0d (expect 400)",  $signed(dut.u_mem.mem[112]));
    $display("addr 116 = %0d (expect 500)",  $signed(dut.u_mem.mem[116]));

    $display("=== Thread 3 Result (base=0x78) ===");
    $display("addr 120 = %0d (expect 10)",   $signed(dut.u_mem.mem[120]));
    $display("addr 124 = %0d (expect 20)",   $signed(dut.u_mem.mem[124]));
    $display("addr 128 = %0d (expect 30)",   $signed(dut.u_mem.mem[128]));
    $display("addr 132 = %0d (expect 40)",   $signed(dut.u_mem.mem[132]));
    $display("addr 136 = %0d (expect 50)",   $signed(dut.u_mem.mem[136]));
    $display("addr 140 = %0d (expect 60)",   $signed(dut.u_mem.mem[140]));
    $display("addr 144 = %0d (expect 70)",   $signed(dut.u_mem.mem[144]));
    $display("addr 148 = %0d (expect 80)",   $signed(dut.u_mem.mem[148]));
    $display("addr 152 = %0d (expect 90)",   $signed(dut.u_mem.mem[152]));
    $display("addr 156 = %0d (expect 100)",  $signed(dut.u_mem.mem[156]));

    $finish;
end
endmodule