`timescale 1ns / 1ps

module tb_branch;

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
    @(negedge clk);
    intf_wen_imem = 1;
    intf_addr_imem = addr;
    intf_data_imem = data;
    @(negedge clk);
    intf_wen_imem = 0;
endtask

initial begin
    clk=0; rst=1;
    intf_wen_imem=0; web=0; dinb=0; addrb=0;
    @(negedge clk);

    // r1 = 0
    load_imem(9'h000, 32'h30010000); // ADDI r1 = 0

    // BEQZ r1, TARGET  (跳到 0x006)
    load_imem(9'h001, 32'h88000003); // imm=3 (依你 ISA offset 規則)

    load_imem(9'h002, 32'h00000000); // delay slot NOP

    // 這三條應該被 flush
    load_imem(9'h003, 32'h3002006F); // ADDI r2 = 111
    load_imem(9'h004, 32'h300300DE); // ADDI r3 = 222
    load_imem(9'h005, 32'h3004014D); // ADDI r4 = 333

    // TARGET:
    load_imem(9'h006, 32'h3005022B); // ADDI r5 = 555

    load_imem(9'h007, 32'h00000000); // NOP

    @(negedge clk);
    rst = 0;

    repeat(50) @(posedge clk);

    $display("=== Branch Verification ===");
    $display("r2 = %0d (expect 0)", dut.u_id.register[2]);
    $display("r3 = %0d (expect 0)", dut.u_id.register[3]);
    $display("r4 = %0d (expect 0)", dut.u_id.register[4]);
    $display("r5 = %0d (expect 555)", dut.u_id.register[5]);
    $display("===========================");

    $finish;
end

endmodule