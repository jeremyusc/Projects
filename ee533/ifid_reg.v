module ifid_reg(
    input clk,
    input rst,
    input flush,

    input  [31:0] i_inst,
    output reg [31:0] o_inst,
	
	input [10:0] i_pc,
	output reg [10:0] o_pc);

always @(posedge clk) begin
    if (rst) begin
        o_inst <= 32'b0;
        o_pc   <= 11'd0;
    end
    else if (flush) begin
        o_inst <= 32'b0;
        o_pc   <= 11'd0;     // branch flush
    end
    else begin
        o_inst <= i_inst;
        o_pc   <= i_pc;
    end
end


endmodule
