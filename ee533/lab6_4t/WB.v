module WB(
                input [63:0] i_mem_data,///DATA MEM
				input [63:0] i_skip_mem,///ALU 
				output [63:0] dout,
				///ctrl
                input i_WRegEn,
                input [3:0] i_WReg1,
				input i_ctrl_mem2reg,
				output  o_ctrl_mem2reg,
                output  o_WRegEn,
                output  [3:0] o_WReg1,
				////thread
				input	[1:0] i_wb_thread,
				output  [1:0] o_wb_thread);
  
  
  
assign o_WRegEn       = i_WRegEn;
assign o_WReg1        = i_WReg1;
assign o_ctrl_mem2reg = i_ctrl_mem2reg;
assign o_wb_thread = i_wb_thread;
  
  assign dout=(o_ctrl_mem2reg) ? i_mem_data : i_skip_mem;
  

endmodule