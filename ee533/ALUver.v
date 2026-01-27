`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    17:34:47 01/24/2026 
// Design Name: 
// Module Name:    ALUver 
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
module ALUver(
    input [31:0] A,
    input [31:0] B,
    input enable,
    input clk,
    input clear,
    input [2:0] op,
    output reg [31:0] ALUout
    );
	reg [31:0] A_r,B_r;
	
	always@(posedge clk) begin
	if(clear) begin
	A_r<=32'h00000000;
	B_r<=32'h00000000;
	ALUout<=32'h00000000;
	end
	else if(enable) begin
	A_r<=A;
	B_r<=B;
	case(op)
		3'b000:
		begin
		ALUout<=A_r+B_r;
		end
		3'b001:
		begin
		ALUout<=A-B;
		end
		3'b010:
		begin
		ALUout<=A_r+A_r;
		end
		3'b011:
		begin
		ALUout<=A_r|B_r;
		end
		3'b100:
		begin
		ALUout<=A_r&B_r;
		end
		default: ALUout<=ALUout;
	endcase
	end
	else begin
	//hold
	end
	end
endmodule

