`timescale 1ns / 1ps

module IF_stage(
    input         clk,
    input         rst,
	
    //interface
    input         intf_wen_imem,
    input  [8:0]  intf_addr_imem,
    input  [31:0] intf_data_imem,

    //output
    output [31:0] data_out,
	output reg [10:0] pc_reg,
	//////ctrl
	input ctrl_branch,
	input [63:0] branch_addr);
	

////////////////PC+4
wire [10:0] pc_reg_next;
assign pc_reg_next = (ctrl_branch) ? (branch_addr[10:0]) : pc_reg + 4;

always @(posedge clk) begin
    if (rst)
        pc_reg <= 0;
	else
        pc_reg <= pc_reg_next;
end



/////////////////
// module
inst_mem m_imem (
	.clk (clk),
    .addr  (pc_reg[10:2]),   
    .wen   (intf_wen_imem),
    .addrb (intf_addr_imem),
    .datab (intf_data_imem),
    .dout  (data_out)
);

endmodule