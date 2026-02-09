module top#(parameter DATA_WIDTH=8)(
input clk_a,clk_b,rst,
input logic [DATA_WIDTH-1:0] i_data
//output logic [DATA_WIDTH-1:0] o_data,
);

logic req,ack;
logic [DATA_WIDTH-1:0] sd_data_bus;
logic [DATA_WIDTH-1:0] rcv_data_bus;


sender #(.DATA_WIDTH(DATA_WIDTH)) m_sender
(.clk_a(clk_a),
.rst(rst),
.ack(ack),
.req(req),
.i_data(i_data),
.o_data(sd_data_bus)
);

rcv #(.DATA_WIDTH(DATA_WIDTH)) m_rcv(
.clk_b(clk_b),
.rst(rst),
.ack(ack),
.req(req),
.i_data(sd_data_bus),
.o_data(rcv_data_bus)
);
 
endmodule