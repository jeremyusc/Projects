`timescale 1ns / 1ps

module tb#(parameter DATA_WIDTH = 8);
/////parameter
//localparam DATA_WIDTH=8;
bit clk_a,clk_b,rst;

class gen;
	rand bit [DATA_WIDTH-1:0] data;
endclass



initial begin
clk_a=0;
clk_b=0;

end


always #10 clk_a=~clk_a;
always #7 clk_b=~clk_b;
logic [DATA_WIDTH-1:0] i_data;
top#(.DATA_WIDTH(DATA_WIDTH)) dut(
.clk_a(clk_a),
.clk_b(clk_b),
.rst(rst),
.i_data(i_data)
);

gen g;

initial begin
	g=new();
	rst=1;
	i_data=0;
	repeat(3) @(posedge clk_a);
	rst=0;
end


initial begin
	for (int i=0;i<20;i++) begin
		wait(dut.req==0);
		assert(g.randomize());
		@(posedge clk_a);
		i_data<=g.data;
		$display("[%0t] SEND %0h", $time, g.data);
		wait(dut.req==0);
	end
end

initial begin
	#300;
	$finish();
end

endmodule