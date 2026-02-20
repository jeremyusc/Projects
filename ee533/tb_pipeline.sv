`timescale 1ns / 1ps

module tb_pipeline;

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

int pass_count, fail_count;

initial begin
    longint signed expected[10];
    longint signed got;
    int i;
    expected[0] = -455;
    expected[1] = -56;
    expected[2] = 0;
    expected[3] = 2;
    expected[4] = 10;
    expected[5] = 65;
    expected[6] = 98;
    expected[7] = 123;
    expected[8] = 125;
    expected[9] = 323;

    clk=0; rst=1;
    intf_wen_imem=0; web=0; dinb=0; addrb=0;
    @(negedge clk);

    // r8=loop flag, r6=compare flag
    // flush 3 cycles: imm = (target - (branch_byte+8+12)) / 4

    load_imem(9'h000, 32'h300F0000); // ADDI r15=0
    load_imem(9'h001, 32'h00000000); // NOP
    load_imem(9'h002, 32'h00000000);
    load_imem(9'h003, 32'h00000000);
    load_imem(9'h004, 32'h00000000);
    load_imem(9'h005, 32'h00000000);
    load_imem(9'h006, 32'h30020000); // ADDI r2=0
    load_imem(9'h007, 32'h00000000); // NOP
    load_imem(9'h008, 32'h00000000);
    load_imem(9'h009, 32'h00000000);
    load_imem(9'h00A, 32'h00000000);
    load_imem(9'h00B, 32'h00000000);
    // ===== OUTER_CHECK: byte 0x030 word 0x00C =====
    load_imem(9'h00C, 32'h30070008); // ADDI r7=8
    load_imem(9'h00D, 32'h00000000); // NOP
    load_imem(9'h00E, 32'h00000000);
    load_imem(9'h00F, 32'h00000000);
    load_imem(9'h010, 32'h00000000);
    load_imem(9'h011, 32'h00000000);
    load_imem(9'h012, 32'hA2780000); // SLT r8=(i<8)
    load_imem(9'h013, 32'h00000000); // NOP x6
    load_imem(9'h014, 32'h00000000);
    load_imem(9'h015, 32'h00000000);
    load_imem(9'h016, 32'h00000000);
    load_imem(9'h017, 32'h00000000);
    load_imem(9'h018, 32'h00000000);
    load_imem(9'h019, 32'h8800004C); // 0x064: BEQZ r8,DONE  imm=0x004C
    load_imem(9'h01A, 32'h00000000); // 0x068: NOP delay slot
    load_imem(9'h01B, 32'h32030001); // 0x06C: ADDI r3=r2+1  j=i+1
    // ===== INNER_CHECK: byte 0x070 word 0x01C =====
    load_imem(9'h01C, 32'h30070009); // ADDI r7=9
    load_imem(9'h01D, 32'h00000000); // NOP
    load_imem(9'h01E, 32'h00000000);
    load_imem(9'h01F, 32'h00000000);
    load_imem(9'h020, 32'h00000000);
    load_imem(9'h021, 32'h00000000);
    load_imem(9'h022, 32'hA3780000); // SLT r8=(j<9)
    load_imem(9'h023, 32'h00000000); // NOP x6
    load_imem(9'h024, 32'h00000000);
    load_imem(9'h025, 32'h00000000);
    load_imem(9'h026, 32'h00000000);
    load_imem(9'h027, 32'h00000000);
    load_imem(9'h028, 32'h00000000);
    load_imem(9'h029, 32'h88000034); // 0x0A4: BEQZ r8,OUTER_INC  imm=0x0034
    load_imem(9'h02A, 32'h00000000); // 0x0A8: NOP delay slot
    // addr_i
    load_imem(9'h02B, 32'hB2090002); // SLL r9=r2<<2
    load_imem(9'h02C, 32'h00000000); // NOP x5
    load_imem(9'h02D, 32'h00000000);
    load_imem(9'h02E, 32'h00000000);
    load_imem(9'h02F, 32'h00000000);
    load_imem(9'h030, 32'h00000000);
    load_imem(9'h031, 32'h19F90000); // ADD r9=r15+r9
    load_imem(9'h032, 32'h00000000); // NOP x5
    load_imem(9'h033, 32'h00000000);
    load_imem(9'h034, 32'h00000000);
    load_imem(9'h035, 32'h00000000);
    load_imem(9'h036, 32'h00000000);
    load_imem(9'h037, 32'h69040000); // LW r4=mem[r9]
    load_imem(9'h038, 32'h00000000); // NOP x5
    load_imem(9'h039, 32'h00000000);
    load_imem(9'h03A, 32'h00000000);
    load_imem(9'h03B, 32'h00000000);
    load_imem(9'h03C, 32'h00000000);
    // addr_j
    load_imem(9'h03D, 32'hB30A0002); // SLL r10=r3<<2
    load_imem(9'h03E, 32'h00000000); // NOP x5
    load_imem(9'h03F, 32'h00000000);
    load_imem(9'h040, 32'h00000000);
    load_imem(9'h041, 32'h00000000);
    load_imem(9'h042, 32'h00000000);
    load_imem(9'h043, 32'h1AFA0000); // ADD r10=r15+r10
    load_imem(9'h044, 32'h00000000); // NOP x5
    load_imem(9'h045, 32'h00000000);
    load_imem(9'h046, 32'h00000000);
    load_imem(9'h047, 32'h00000000);
    load_imem(9'h048, 32'h00000000);
    load_imem(9'h049, 32'h6A050000); // LW r5=mem[r10]
    load_imem(9'h04A, 32'h00000000); // NOP x5
    load_imem(9'h04B, 32'h00000000);
    load_imem(9'h04C, 32'h00000000);
    load_imem(9'h04D, 32'h00000000);
    load_imem(9'h04E, 32'h00000000);
    // compare
    load_imem(9'h04F, 32'hA5460000); // SLT r6=(r5<r4)
    load_imem(9'h050, 32'h00000000); // NOP x6
    load_imem(9'h051, 32'h00000000);
    load_imem(9'h052, 32'h00000000);
    load_imem(9'h053, 32'h00000000);
    load_imem(9'h054, 32'h00000000);
    load_imem(9'h055, 32'h00000000);
    load_imem(9'h056, 32'h8600FFFF); // 0x158: BEQZ r6,NO_SWAP  imm=0xFFFF
    load_imem(9'h057, 32'h00000000); // 0x15C: NOP delay slot
    // swap
    load_imem(9'h058, 32'h79500000); // 0x160: SW mem[r9]=r5
    load_imem(9'h059, 32'h7A400000); // 0x164: SW mem[r10]=r4
    // ===== NO_SWAP / INNER_INC: byte 0x168 word 0x05A =====
    load_imem(9'h05A, 32'h33030001); // 0x168: ADDI r3=r3+1  j++
    load_imem(9'h05B, 32'h00000000); // NOP x5
    load_imem(9'h05C, 32'h00000000);
    load_imem(9'h05D, 32'h00000000);
    load_imem(9'h05E, 32'h00000000);
    load_imem(9'h05F, 32'h00000000);
    load_imem(9'h060, 32'h8800FFB7); // 0x180: BEQZ r0,INNER_CHECK  imm=0xFFB7
    load_imem(9'h061, 32'h00000000); // 0x184: NOP delay slot
    // ===== OUTER_INC: byte 0x188 word 0x062 =====
    load_imem(9'h062, 32'h32020001); // 0x188: ADDI r2=r2+1  i++
    load_imem(9'h063, 32'h00000000); // NOP x5
    load_imem(9'h064, 32'h00000000);
    load_imem(9'h065, 32'h00000000);
    load_imem(9'h066, 32'h00000000);
    load_imem(9'h067, 32'h00000000);
    load_imem(9'h068, 32'h8800FF9F); // 0x1A0: BEQZ r0,OUTER_CHECK  imm=0xFF9F
    load_imem(9'h069, 32'h00000000); // 0x1A4: NOP delay slot
    // ===== DONE: byte 0x1A8 word 0x06A =====
    load_imem(9'h06A, 32'h00000000); // NOP

    // ===== Data Memory =====
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

    @(negedge clk);
    rst = 0;

    repeat(300000) @(posedge clk);

    pass_count = 0;
    fail_count = 0;

    $display("==============================");
    $display("  Bubble Sort Result Check");
    $display("==============================");
    $display("idx | expected | got      | result");
    $display("----+----------+----------+-------");

    for (i = 0; i < 10; i = i + 1) begin
        got = $signed(dut.u_mem.mem[i*4]);
        if (got === expected[i]) begin
            $display(" %0d  | %6d   | %6d   | PASS", i, expected[i], got);
            pass_count++;
        end else begin
            $display(" %0d  | %6d   | %6d   | FAIL <<<", i, expected[i], got);
            fail_count++;
        end
    end

    $display("==============================");
    $display("  PASS: %0d / 10", pass_count);
    if (fail_count == 0)
        $display("  ALL PASS! Bubble sort correct.");
    else
        $display("  FAIL: %0d error(s).", fail_count);
    $display("==============================");
    $finish;
end

initial begin
    #30000000;
    $display("TIMEOUT");
    $finish;
end

initial begin
    $dumpfile("tb_pipeline.vcd");
    $dumpvars(0, tb_pipeline);
end

endmodule