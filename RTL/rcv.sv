module rcv#(parameter DATA_WIDTH=8)(
  input clk_b,
  input logic rst,req,
  output logic ack,
  input logic [DATA_WIDTH-1:0] i_data,
  output logic [DATA_WIDTH-1:0] o_data
);
  

  logic  r_1,r_2;

  always @ (posedge clk_b) begin
    if(rst) begin
      r_1<=0;
      r_2<=0;
    end
    else begin
      r_1<=req;
      r_2<=r_1;
      end     
    end

  
  always @ (posedge clk_b) begin
    if(rst) begin
      o_data<=0;
      ack<=0;
    end
    else begin
      if(r_2) begin
        o_data<=i_data;
        ack<=1;
      end
      else begin
        ack<=0;
  end
    end
  end
  
endmodule