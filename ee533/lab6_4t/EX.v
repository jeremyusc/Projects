module EX_stage(
input clk,
input rst,
input  [63:0] R1,
input  [63:0] R2,
input  [63:0] sign_extended,

input  alu_src,
input  [2:0] ALU_op,
////thread
input	[1:0] i_wb_thread,
output reg [1:0] o_wb_thread,
/////////MEM&WB
input  [3:0] i_WReg1,
input        i_WRegEn,
input        i_WMemEn,
input        i_RMemEn,
input        i_ctrl_mem2reg,
output reg [63:0] o_alu_result,
output reg [63:0] o_write_data,

output reg [3:0]  o_WReg1,
output reg        o_WRegEn,
output reg        o_WMemEn,
output reg        o_RMemEn,
output reg        o_ctrl_mem2reg
);


//////////////////ALU COMB
wire [63:0] temp_R2;
assign temp_R2 = (alu_src) ? sign_extended : R2;

reg [63:0] alu_result;

parameter ADD = 3'd0;
parameter SUB = 3'd1;
parameter AND = 3'd2;
parameter OR  = 3'd3;
parameter SLT = 3'd4;
parameter SLL = 3'd5;

always @(*) begin
    case(ALU_op)
        ADD : alu_result = R1 + temp_R2;
        SUB : alu_result = R1 - temp_R2;
        AND : alu_result = R1 & temp_R2;
        OR  : alu_result = R1 | temp_R2;
        SLT : alu_result =
               ($signed(R1) < $signed(temp_R2)) ? 64'd1 : 64'd0;
        SLL : alu_result = R1 << temp_R2[5:0];
        default: alu_result = 64'd0;
    endcase
end


////////////////////EX/MEM REG
always @(posedge clk) begin
    if (rst) begin
        o_alu_result   <= 64'd0;
        o_write_data   <= 64'd0;
		//////
        o_WReg1        <= 4'd0;
        o_WRegEn       <= 1'b0;
        o_WMemEn       <= 1'b0;
        o_RMemEn       <= 1'b0;
        o_ctrl_mem2reg <= 1'b0;
		/////
		o_wb_thread		<= 2'd0;
    end
    else begin
        o_alu_result   <= alu_result; 
        o_write_data   <= R2;         
////////////////////////////
        o_WReg1        <= i_WReg1;
        o_WRegEn       <= i_WRegEn;
        o_WMemEn       <= i_WMemEn;
        o_RMemEn       <= i_RMemEn;
        o_ctrl_mem2reg <= i_ctrl_mem2reg;
		o_wb_thread		<=i_wb_thread;
    end
end
endmodule