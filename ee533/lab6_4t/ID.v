module ID(input  clk,rst,
			input [31:0] i_inst,

            input  [3:0] waddr,
            input  [63:0]wdata,
			   
			//input [15:0] i_sign_extended,////I-type
			input [10:0] ifid_pc,
			output [63:0] r0data,
			
            output [63:0] r1data,
			output [63:0] o_sign_extended,
			/////control signal////////////
			input i_WRegEn,
			output [3:0] o_WReg1,
			output reg o_WRegEn,/////
			output reg o_WMemEn,
			output reg o_RMemEn,////////
			output reg alusrc,
			output reg [2:0] ALU_op,
			output reg ctrl_mem2reg,///////
			///////branch///////////
			input [1:0] id_thread,
			input [1:0] wb_thread,
			output reg ctrl_branch,////////
			output [1:0] branch_id_thread,
			output [63:0] branch_addr);
			     
				 
				 
  
  reg [63:0] register[0:3] [0:15];
  integer i,j;
wire equal;
  	wire [3:0] r0addr;
	wire [3:0] r1addr;
	assign r0data = (r0addr == 4'd0) ? 64'd0 : register[id_thread][r0addr];//////////////
	assign r1data = (r1addr == 4'd0) ? 64'd0 : register[id_thread][r1addr];///////////////////

  ////////////////////////// regfile
  
  always @(posedge clk) begin
  if(rst) begin
	for(i=0;i<4;i=i+1) begin
		for(j=0;j<16;j=j+1) begin
		register[i][j]<=64'd0;
		end
	end
  end else begin 
    if(i_WRegEn && waddr!=4'd0 ) 
		register[wb_thread][waddr]<=wdata;
  end
  end
 



 //////////////////////////
	wire [3:0] op;
	wire [15:0] i_sign_extended;
	wire [63:0] sign_extended;
	wire [3:0] WReg1;
	wire zero;
	
assign o_WReg1= WReg1;
 assign op=i_inst[31:28];
 assign r0addr=i_inst[27:24];
 assign r1addr=i_inst[23:20];
 assign WReg1=i_inst[19:16];
 assign i_sign_extended=i_inst[15:0];
 assign o_sign_extended=sign_extended;
 ///////////////////branch
 assign equal = (r0data == r1data);
  assign branch_addr =   {53'd0, ifid_pc} + (sign_extended /*<< 2*/);
  assign branch_id_thread = id_thread;
 assign zero = (r0data == 64'd0);
 assign sign_extended={{48{i_sign_extended[15]}},i_sign_extended[15:0]};
 ///////////////control unit
 parameter NOP= 4'd0;
 parameter ADD =4'd1;
 parameter SUB =4'd2;
 parameter ADDI= 4'd3;
 parameter AND=4'd4;
 parameter OR =4'd5;
 parameter LW =4'd6;
 parameter SW =4'd7;
 parameter BEQZ= 4'd8;
 parameter BNEZ=4'd9;
 parameter SLT =4'd10;
 parameter SLL = 4'd11;
  parameter BEQ = 4'd12;

 //////////ctrl_mem2reg
 /////////ctrl_branch
 always @(*) begin
	o_WRegEn     = 0;
    o_WMemEn       = 0;
    o_RMemEn       = 0;
    ctrl_mem2reg = 0;
    alusrc       = 0;
    ALU_op       = 3'd0;
    ctrl_branch  = 0;
	case(op)
	//////////////////RRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR
	//ALU_op 0:ADD 
	//		1:SUB 
	//		2:AND 
	//		3:OR 
	//		4:SLT 
	//		5:shift
	NOP:begin
		////NOP
	end
	ADD: begin
		o_WRegEn = 1;
		alusrc=0;
		ALU_op=3'd0;/////ADD
	end
	SUB:begin
		o_WRegEn = 1;
		alusrc=0;
		ALU_op=3'd1;/////////SUB
	end
	AND:begin
		o_WRegEn = 1;
		alusrc=0;
		ALU_op=3'd2;/////AND
	end
	OR:begin
		o_WRegEn = 1;
		alusrc=0;
		ALU_op=3'd3;/////OR
	end
	SLT:begin
        o_WRegEn = 1;
        alusrc   = 0;
        ALU_op   = 3'd4;  // SLT
    end
	///////////////////////IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
	ADDI:begin
        o_WRegEn = 1;
        alusrc   = 1;
        ALU_op   = 3'd0;  // ADD
    end
	LW:begin
        o_WRegEn     = 1;
        o_RMemEn       = 1;
        ctrl_mem2reg = 1;
        alusrc       = 1;
        ALU_op       = 3'd0;  // ADD for addr
    end
	SW:begin
        o_WMemEn = 1;
        alusrc = 1;
        ALU_op = 3'd0;  // ADD for addr
    end
	BEQZ: begin
        ctrl_branch = zero;  ///branch
    end
	BNEZ: begin
        ctrl_branch = ~zero;  ///branch
    end
	BEQ: begin                   
        ctrl_branch = equal;      
    end
	SLL:begin
    o_WRegEn = 1;
    alusrc   = 1;
    ALU_op   = 3'd5;  // shift left logic
end
	default: ;
 endcase
end
 
 always @(posedge clk) begin
    if(op == BEQZ)
        $display("BEQZ: ifid_pc=%0d, imm=%0d, branch_addr=%0d",
                 ifid_pc, sign_extended, branch_addr);
end




always @(posedge clk) begin
    if(op == BEQ)
        $display("BEQ: ifid_pc=%0d, r%0d=%0d, r%0d=%0d, equal=%0d, branch_addr=%0d",
                 ifid_pc, r0addr, r0data, r1addr, r1data, equal, branch_addr);
end
 endmodule 
 
 