`timescale 1ns/1ps
module inst_mem(
    input   clk,
    input [8:0] addr,

    ////interface
    input wen,
    input [8:0] addrb,
    input [31:0] datab,

    /////output
    output wire [31:0] dout
);
    reg [31:0] mem [0:511];

    assign dout = mem[addr];
 
 
 
    always @(posedge clk) begin
        if(wen)
            mem[addrb] <= datab;
    end
endmodule