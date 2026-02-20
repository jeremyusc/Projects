`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    02:27:35 02/13/2026 
// Design Name: 
// Module Name:    Data_mem 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module data_mem(
    input clk,
    input [63:0] addr,
	input [63:0] dina,
    input WMemEn,
	
	output reg [63:0] dout,
	output reg [63:0] skip_mem,
	
	
	////WB
	input  i_WRegEn,
    input [3:0] i_WReg1,
	input i_ctrl_mem2reg,
	output reg o_MRegEn,
	output reg [3:0] o_WReg1,
	output reg o_ctrl_mem2reg,
	////interface
	input web,
	input [63:0] dinb,
    input [7:0] addrb);
	
	wire [7:0] addra;
	
	assign addra = addr[7:0];
	
	
    reg [63:0] mem [0:255];
	////////////
	/////////////////
	
	
	///////////////
	/////////////////////////
/////mem_write/read
    always @(posedge clk) begin
        if (WMemEn) begin
            mem[addra] <= dina;
			 $display("SW: mem[%0d] <= %0d  (addr=%0d)", addra, $signed(dina), $signed(addr));
		end	
		 if (i_ctrl_mem2reg) begin
            $display("LW: mem[%0d] => %0d  (addr=%0d)", addra, $signed(mem[addra]), $signed(addr));
        end
			dout <= mem[addra];
		skip_mem <= addr;
    end
////////////////////////
//ctrl
always @(posedge clk) begin
	o_WReg1<=i_WReg1;
	o_MRegEn<=i_WRegEn;
	o_ctrl_mem2reg<=i_ctrl_mem2reg;
end


///////////interface
	always @(posedge clk) begin
	if(web)
		mem[addrb]<=dinb;
	end

endmodule