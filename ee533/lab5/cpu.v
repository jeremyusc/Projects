// =============================================================================
//  BUBBLE SORT FOR 5-STAGE PIPELINE
//
//  Author:
//      ██╗███████╗██████╗ ███████╗███╗   ███╗██╗   ██╗
//      ██║██╔════╝██╔══██╗██╔════╝████╗ ████║╚██╗ ██╔╝
//      ██║█████╗  ██████╔╝█████╗  ██╔████╔██║ ╚████╔╝ 
//  ██╗ ██║██╔══╝  ██╔══██╗██╔══╝  ██║╚██╔╝██║  ╚██╔╝  
//  ╚█████╔╝███████╗██║  ██║███████╗██║ ╚═╝ ██║   ██║   
//   ╚════╝ ╚══════╝╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝   ╚═╝   
//                                   
// =============================================================================

`timescale 1ns / 1ps

module pipeline_top(
    input clk,
    input rst,

    // instruction memory programming interface
    input         intf_wen_imem,
    input  [8:0]  intf_addr_imem,
    input  [31:0] intf_data_imem,

    // data memory programming interface
    input         web,
    input  [63:0] dinb,
    input  [7:0]  addrb
);

//////////////////////////
// IF stage
//////////////////////////

wire [31:0] if_inst;
wire [10:0] if_pc;

wire [63:0] branch_addr;
wire        ctrl_branch;

reg ctrl_branch_r;
reg ctrl_branch_r2;
reg ctrl_branch_r3;
always @(posedge clk) begin
    ctrl_branch_r  <= ctrl_branch;
    ctrl_branch_r2 <= ctrl_branch_r;
    ctrl_branch_r3 <= ctrl_branch_r2;
end

//wire ifid_flush = ctrl_branch | ctrl_branch_r | ctrl_branch_r2;
wire ifid_flush = ctrl_branch;
IF_stage u_if(
    .clk(clk),
    .rst(rst),

    .intf_wen_imem(intf_wen_imem),
    .intf_addr_imem(intf_addr_imem),
    .intf_data_imem(intf_data_imem),

    .data_out(if_inst),
    .pc_reg(if_pc),

    .ctrl_branch(ctrl_branch),
    .branch_addr(branch_addr)
);

//////////////////////////
// IF/ID
//////////////////////////

wire [31:0] id_inst;
wire [10:0] id_pc;

ifid_reg u_ifid(
    .clk(clk),
    .rst(rst),
    .flush(ifid_flush),//////

    .i_inst(if_inst),
    .o_inst(id_inst),
    .i_pc(if_pc),
    .o_pc(id_pc)
);

//////////////////////////
// ID stage
//////////////////////////

wire [63:0] id_R1, id_R2;
wire [63:0] id_sign_ext;
wire [3:0]  id_WReg1;
wire        id_WRegEn, id_WMemEn, id_RMemEn;
wire        id_ctrl_mem2reg;
wire        id_alusrc;
wire [2:0]  id_ALU_op;

// writeback wires
wire [63:0] wb_data;
wire [3:0]  wb_waddr;
wire        wb_wen;

ID u_id(
    .clk(clk),
    .rst(rst),
    .i_inst(id_inst),

    .waddr(wb_waddr),
    .wdata(wb_data),
    .i_WRegEn(wb_wen),

    .ifid_pc(id_pc),

    .r0data(id_R1),
    .r1data(id_R2),
    .o_sign_extended(id_sign_ext),

    .o_WReg1(id_WReg1),
    .o_WRegEn(id_WRegEn),
    .o_WMemEn(id_WMemEn),
    .o_RMemEn(id_RMemEn),
    .ctrl_branch(ctrl_branch),
    .ctrl_mem2reg(id_ctrl_mem2reg),
    .branch_addr(branch_addr),
    .alusrc(id_alusrc),
    .ALU_op(id_ALU_op)
);

//////////////////////////
// ID/EX
//////////////////////////

wire [63:0] ex_R1, ex_R2, ex_sign_ext;
wire [3:0]  ex_WReg1;
wire        ex_WRegEn, ex_WMemEn, ex_RMemEn;
wire        ex_ctrl_mem2reg;
wire        ex_alusrc;
wire [2:0]  ex_ALU_op;

idex_reg u_idex(
    .clk(clk),
    .rst(rst),
	 .flush(0), 
	 
	 
    .i_R1(id_R1),
    .i_R2(id_R2),
    .i_sign_extended(id_sign_ext),

    .o_R1(ex_R1),
    .o_R2(ex_R2),
    .o_sign_extended(ex_sign_ext),

    .i_WReg1(id_WReg1),
    .i_WRegEn(id_WRegEn),
    .i_WMemEn(id_WMemEn),
    .i_RMemEn(id_RMemEn),
    .i_ctrl_mem2reg(id_ctrl_mem2reg),

    .o_WReg1(ex_WReg1),
    .o_WRegEn(ex_WRegEn),
    .o_WMemEn(ex_WMemEn),
    .o_RMemEn(ex_RMemEn),
    .o_ctrl_mem2reg(ex_ctrl_mem2reg),

    .i_alusrc(id_alusrc),
    .i_ALU_op(id_ALU_op),
    .o_alusrc(ex_alusrc),
    .o_ALU_op(ex_ALU_op)
);

//////////////////////////
// EX stage
//////////////////////////

wire [63:0] ex_alu_result;
wire [63:0] ex_write_data;
wire [3:0]  mem_WReg1;
wire        mem_WRegEn, mem_WMemEn, mem_RMemEn;
wire        mem_ctrl_mem2reg;

EX_stage u_ex(
    .clk(clk),
    .rst(rst),

    .R1(ex_R1),
    .R2(ex_R2),
    .sign_extended(ex_sign_ext),

    .alu_src(ex_alusrc),
    .ALU_op(ex_ALU_op),

    .i_WReg1(ex_WReg1),
    .i_WRegEn(ex_WRegEn),
    .i_WMemEn(ex_WMemEn),
    .i_RMemEn(ex_RMemEn),
    .i_ctrl_mem2reg(ex_ctrl_mem2reg),

    .o_alu_result(ex_alu_result),
    .o_write_data(ex_write_data),

    .o_WReg1(mem_WReg1),
    .o_WRegEn(mem_WRegEn),
    .o_WMemEn(mem_WMemEn),
    .o_RMemEn(mem_RMemEn),
    .o_ctrl_mem2reg(mem_ctrl_mem2reg)
);

//////////////////////////
// MEM stage
//////////////////////////

wire [63:0] mem_data_out;
wire [63:0] mem_skip;
wire [3:0]  wb_reg;
wire        wb_reg_en;
wire        wb_ctrl_mem2reg;

data_mem u_mem(
    .clk(clk),

    .addr(ex_alu_result),
    .dina(ex_write_data),
    .WMemEn(mem_WMemEn),

    .dout(mem_data_out),
    .skip_mem(mem_skip),

    .i_WRegEn(mem_WRegEn),
    .i_WReg1(mem_WReg1),
    .i_ctrl_mem2reg(mem_ctrl_mem2reg),

    .o_MRegEn(wb_reg_en),
    .o_WReg1(wb_reg),
    .o_ctrl_mem2reg(wb_ctrl_mem2reg),

    .web(web),
    .dinb(dinb),
    .addrb(addrb)
);

//////////////////////////
// WB stage
//////////////////////////

WB u_wb(
    .i_mem_data(mem_data_out),
    .i_skip_mem(mem_skip),
    .dout(wb_data),

    .i_WRegEn(wb_reg_en),
    .i_WReg1(wb_reg),
    .i_ctrl_mem2reg(wb_ctrl_mem2reg),

    .o_WRegEn(wb_wen),
    .o_WReg1(wb_waddr),
    .o_ctrl_mem2reg()
);

endmodule