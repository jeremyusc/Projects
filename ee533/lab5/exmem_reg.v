module exmem_reg(input  clk,

                input  [63:0] i_R1,
                input  [63:0] i_R2,
				output reg [63:0] o_R1,
                output reg [63:0] o_R2,
				//////////MEM&WB
               input  [3:0] i_WReg1,
               input  i_WRegEn,
               input  i_WMemEn,	
			   input i_RMemEn,
			   input i_ctrl_mem2reg,
			
               output reg o_WRegEn,
               output reg o_WMemEn,
			   output reg o_RMemEn,
			   output reg o_ctrl_mem2reg,
               output reg [3:0] o_WReg1);
  
  
  
  always @(posedge clk) begin
    o_R1<=i_R1;
    o_R2<=i_R2;
	  //////MEM&WB
    o_WReg1<=i_WReg1;
    o_WRegEn<=i_WRegEn;
    o_WMemEn<=i_WMemEn;
	o_RMemEn<=i_RMemEn;
	o_ctrl_mem2reg<=i_ctrl_mem2reg;
	  end
endmodule