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

    // r1~r9 = 1~9
load_imem(9'h000, 32'h80000028); // BEQZ r0, imm=40
load_imem(9'h001, 32'h00000000); // NOP (delay slot，會被 flush)

// 這幾條應該被跳過
load_imem(9'h002, 32'h30010001); // ADDI r1=1
load_imem(9'h003, 32'h30020002); // ADDI r2=2
load_imem(9'h004, 32'h30030003); // ADDI r3=3
load_imem(9'h005, 32'h30040004); // ADDI r4=4
load_imem(9'h006, 32'h30050005); // ADDI r5=5
load_imem(9'h007, 32'h30060006); // ADDI r6=6
load_imem(9'h008, 32'h30070007); // ADDI r7=7
load_imem(9'h009, 32'h30080008); // ADDI r8=8
// word 0x009 還差一條，視需要可以加 r9

// TARGET word 0x00A：只寫 r10
load_imem(9'h00A, 32'h300A000A); // ADDI r10=10
load_imem(9'h00B, 32'h00000000); // NOP x4
load_imem(9'h00C, 32'h00000000);
load_imem(9'h00D, 32'h00000000);
load_imem(9'h00E, 32'h00000000);



    @(negedge clk);
    rst = 0;
repeat(100) begin
@(posedge clk);
$display("PC=%0d | wb_wen=%b wb_waddr=%0d wb_data=%0d",
             dut.u_if.pc_reg,
             dut.wb_wen,
             dut.wb_waddr,
             dut.wb_data);
$display("PC=%0d | ex_WReg=%0d mem_WReg=%0d wb_reg=%0d wb_waddr=%0d",
             dut.u_if.pc_reg,
             dut.ex_WReg1,
             dut.mem_WReg1,
             dut.wb_reg,
             dut.wb_waddr);			
    $display("PC=%0d | id_WReg1=%0d id_WRegEn=%0d",
             dut.u_if.pc_reg,
             dut.id_WReg1,
             dut.id_WRegEn);			 
$display("PC=%0d", dut.u_if.pc_reg);
/*repeat(100) @(posedge clk);
$display("r11 = %0d", dut.u_id.register[11]);
$display("r1  = %0d", dut.u_id.register[1]);*/
end
    repeat(100) @(posedge clk);

    $display("=== Store + Branch Test ===");
    $display("r1  = %0d (expect 1)",  dut.u_id.register[1]);
    $display("r2  = %0d (expect 2)",  dut.u_id.register[2]);
    $display("r3  = %0d (expect 3)",  dut.u_id.register[3]);
    $display("r4  = %0d (expect 4)",  dut.u_id.register[4]);
    $display("r5  = %0d (expect 5)",  dut.u_id.register[5]);
    $display("r6  = %0d (expect 6)",  dut.u_id.register[6]);
    $display("r7  = %0d (expect 7)",  dut.u_id.register[7]);
    $display("r8  = %0d (expect 8)",  dut.u_id.register[8]);
    $display("r9  = %0d (expect 9)",  dut.u_id.register[9]);
    $display("r10 = %0d (expect 10)", dut.u_id.register[10]);
    $display("===========================");
    $finish;
end

endmodule


