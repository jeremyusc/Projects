module idex_reg(
    input clk,
    input rst,
	input flush,
///////////////////////data
    input  [63:0] i_R1,
    input  [63:0] i_R2,
    input  [63:0] i_sign_extended,
    output reg [63:0] o_R1,
    output reg [63:0] o_R2,
    output reg [63:0] o_sign_extended,
//////////////////////////MEM
    input  [3:0] i_WReg1,
    input        i_WRegEn,
    input        i_WMemEn,
    input        i_RMemEn,
    input        i_ctrl_mem2reg,
    output reg [3:0] o_WReg1,
    output reg       o_WRegEn,
    output reg       o_WMemEn,
    output reg       o_RMemEn,
    output reg       o_ctrl_mem2reg,
/////////////////////EX
    input        i_alusrc,
    input  [2:0] i_ALU_op,
    output reg       o_alusrc,
    output reg [2:0] o_ALU_op
);

always @(posedge clk) begin
    if (rst || flush) begin
        o_R1            <= 64'd0;
        o_R2            <= 64'd0;
        o_sign_extended <= 64'd0;
        o_WReg1         <= 4'd0;
        o_WRegEn        <= 1'b0;
        o_WMemEn        <= 1'b0;
        o_RMemEn        <= 1'b0;
        o_ctrl_mem2reg  <= 1'b0;
        o_alusrc        <= 1'b0;
        o_ALU_op        <= 3'd0;
    end else begin
        o_R1            <= i_R1;
        o_R2            <= i_R2;
        o_sign_extended <= i_sign_extended;
        o_WReg1         <= i_WReg1;
        o_WRegEn        <= i_WRegEn;
        o_WMemEn        <= i_WMemEn;
        o_RMemEn        <= i_RMemEn;
        o_ctrl_mem2reg  <= i_ctrl_mem2reg;
        o_alusrc        <= i_alusrc;
        o_ALU_op        <= i_ALU_op;
    end
end

endmodule