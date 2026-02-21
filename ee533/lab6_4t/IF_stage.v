`timescale 1ns / 1ps
module IF_stage(
    input         clk,
    input         rst,
    
    // interface
    input         intf_wen_imem,
    input  [8:0]  intf_addr_imem,
    input  [31:0] intf_data_imem,

    // output
    output [31:0] data_out,
    output [10:0] pc_out,
    
    // ctrl_thread 
    input  [1:0]  ctrl_thread,    
    input  [1:0]  branch_id_thread,  
	output  [1:0]  o_ctrl_thread,
    // ctrl_branch 
    input         ctrl_branch,      
    
    input  [63:0] branch_addr);

reg  [10:0] pc_reg [0:3];
integer i;

always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < 4; i = i + 1) begin
            pc_reg[i] <= 11'd0;
        end
    end else begin
        for (i = 0; i < 4; i = i + 1) begin
            ////branch_tag
            if (ctrl_branch && (branch_id_thread == i[1:0])) begin
                pc_reg[i] <= branch_addr[10:0];
            end 
            ////pc+4
            else if (ctrl_thread == i[1:0]) begin
                pc_reg[i] <= pc_reg[i] + 4;
            end
            
        end
    end
end

assign pc_out = pc_reg[ctrl_thread];


	assign o_ctrl_thread =ctrl_thread;


/////////////////
// Inst Memory
inst_mem m_imem (
    .clk   (clk),
    .addr  (pc_out[10:2]),   
    .wen   (intf_wen_imem),
    .addrb (intf_addr_imem),
    .datab (intf_data_imem),
    .dout  (data_out)
);
endmodule