module EX#(
    parameter DATA_WIDTH = 32;
    parameter ADDR = 10;
)(
    input clk, rst,
    input [3:0] ex_alu_op,
    input [4:0] ex_rs1, ex_rs2, ex_rd,
    input [DATA_WIDTH-1:0] ex_imm,
    input [1:0] rs_type,
    input ex_rs2_is_imm,

    output reg 
);





endmodule