`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer:
//
// Create Date:   17:51:31 01/24/2026
// Design Name:   ALUver
// Module Name:   C:/Documents and Settings/student/isetest/lab2/ALUtb.v
// Project Name:  lab2
// Target Device:  
// Tool versions:  
// Description: 
//
// Verilog Test Fixture created by ISE for module: ALUver
//
// Dependencies:
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
////////////////////////////////////////////////////////////////////////////////

module ALUtb;

	// Inputs
	reg [31:0] A;
	reg [31:0] B;
	reg enable;
	reg clk;
	reg clear;
	reg [2:0] op;

	// Outputs
	wire [31:0] ALUout;

	// Instantiate the Unit Under Test (UUT)
	ALUver dut (
		.A(A), 
		.B(B), 
		.enable(enable), 
		.clk(clk), 
		.clear(clear), 
		.op(op), 
		.ALUout(ALUout)
	);

	always #50 clk=~clk; 

	initial begin
		// Initialize Inputs
		A = 0;
		B = 0;
		enable = 0;
		clk = 0;
		clear = 1;
		op = 0;

		// Wait 100 ns for global reset to finish
		#100;
        clear=0;
		  enable=1;
		// Add stimulus here
	//ADD
	A=10;
	B=3;
	op=3'b000;
	#200;
	//SUB
	op=3'b001;
	#100;
	//shift
	op=3'b010;
	#100;
	//or
	op=3'b011;
	#100;
	//and
	op=3'b100;
	#200;
	clear=1;
	#150;
	clear=0;
	#100;
	enable=0;
	#300;
	$finish();
	end
      
endmodule

