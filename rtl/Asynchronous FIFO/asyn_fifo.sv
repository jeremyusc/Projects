module asyn_fifo#(parameter PTR_WIDTH=4,parameter DEPTH=1<<PTR_WIDTH,parameter DATA_WIDTH=8)(
  input logic wclk,rclk,rst_n,
  input logic w_en, r_en,
  input logic [DATA_WIDTH-1:0] wdata,
  output logic [DATA_WIDTH-1:0] rdata);
  
  
  logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
  logic full,empty;
  logic [PTR_WIDTH:0] b_wptr,b_rptr;
  logic [PTR_WIDTH:0] g_wptr,g_rptr;
  
  
logic [PTR_WIDTH:0] b_wptr_next;
logic [PTR_WIDTH:0] g_wptr_next;

assign b_wptr_next = b_wptr + w_en;
assign g_wptr_next = b_wptr_next ^ (b_wptr_next >> 1);

  

/////////////////write//////////////////
	assign full=(g_wptr_next=={~g_rptr_syn[PTR_WIDTH:PTR_WIDTH-1],
								g_rptr_syn[PTR_WIDTH-2:0]});
	
always @(posedge wclk) begin
	if(!rst_n)begin
		b_wptr<=0;
	end
	else begin
		if(!full&&w_en) begin
			mem[b_wptr[PTR_WIDTH-1:0]]<=wdata;
			b_wptr<=b_wptr+1;
		end
	end
end


/////////////////read////////////////////////
  logic [PTR_WIDTH:0] b_rptr_next;
  logic [PTR_WIDTH:0] g_rptr_next;
  
assign b_rptr_next = b_rptr + r_en;
assign g_rptr_next = b_rptr_next ^ (b_rptr_next >> 1);

	assign empty = (g_rptr_next==g_wptr_syn);
	always @(posedge rclk) begin
		if(!rst_n)begin
			b_rptr<=0;
		end
		else begin
			if(!empty&&r_en) begin
			rdata<=mem[b_rptr[PTR_WIDTH-1:0]];
			b_rptr<=b_rptr_next;
			end
		end
	end
	
////////////////b2g&&g2b//////////////////////
logic [PTR_WIDTH:0] gb_rptr_syn;
logic [PTR_WIDTH:0] gb_wptr_syn;

	assign g_wptr=b_wptr^(b_wptr>>1);

	assign g_rptr=b_rptr^(b_rptr>>1);
	
function automatic [PTR_WIDTH:0] gray2bin(input [PTR_WIDTH:0] g);
    automatic logic [PTR_WIDTH:0] b;
    b[PTR_WIDTH] = g[PTR_WIDTH];
    for (int i = PTR_WIDTH-1; i >= 0; i--)
        b[i] = b[i+1] ^ g[i];
    return b;
endfunction

assign gb_wptr_syn = gray2bin(g_wptr_syn);
assign gb_rptr_syn = gray2bin(g_rptr_syn);

/////////////////synchro//////////////////////
logic [PTR_WIDTH:0] g_wptr_syn,g_rptr_syn;
logic [PTR_WIDTH:0] temp_w,temp_r;
	always @(posedge rclk) begin
		if(!rst_n) begin
			temp_w<=0;
			g_wptr_syn<=0;
		end
		else begin
			temp_w<=g_wptr;
			g_wptr_syn<=temp_w;
		end
	end

	always @(posedge wclk) begin
		if(!rst_n) begin
			temp_r<=0;
			g_rptr_syn<=0;
		end
		else begin
			temp_r<=g_rptr;
			g_rptr_syn<=temp_r;
		end
	end

  
  
endmodule
