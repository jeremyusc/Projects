module ifid_reg(
    input clk,
    input rst,

    input  [31:0] i_inst,
    output reg [31:0] o_inst,
	
	///thread
	input [1:0] i_thread,
	output reg[1:0] o_thread,
	
	input [10:0] i_pc,
	output reg [10:0] o_pc);

always @(posedge clk) begin
    if (rst) begin
        o_inst <= 32'b0;
        o_pc   <= 11'd0;
    end
    else begin
        o_inst <= i_inst;
        o_pc   <= i_pc;
		///thread
		o_thread<=i_thread;	
    end
end


endmodule