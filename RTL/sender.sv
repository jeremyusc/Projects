module  sender #(parameter DATA_WIDTH=8)
(
input clk_a,rst,
input logic ack,
  input logic [DATA_WIDTH-1:0] i_data,
output logic req,
  output logic [DATA_WIDTH-1:0] o_data
);
 
  logic a_1,a_2;
  
  always @ (posedge clk_a) begin
    if(rst) begin
      a_1<=0;
      a_2<=0;
    end
    else begin
      a_1<=ack;
      a_2<=a_1;
  end
  end
    
    always @(posedge clk_a) begin
      if(rst) begin
        req<=0;
        o_data<=0;
      end
      else begin
        if(!req && !a_2) begin
          req<=1;
          o_data<=i_data;
        end
        else if (a_2) 
          req<=0;
      end
    end
endmodule