module BPB#(
    parameter ADDR = 10,
    parameter BPB_ENTRY = 16 
)(
    input clk, rst,
    input [ADDR-1:0] current_pc,
    output branch_taken,
    ////update
    input [ADDR-1:0] update_pc,
    input update_en,
    input actual_taken
);///2-bit

localparam IDX = $clog2(BPB_ENTRY);
reg [1:0] pht [0:BPB_ENTRY-1];

wire [IDX-1:0] index = current_pc[IDX+1:2];
wire [IDX-1:0] update_index = update_pc[IDX+1:2];

assign branch_taken = pht[index][1];

integer i;
always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < BPB_ENTRY; i = i + 1)
            pht[i] <= 2'b01; 
    end else if(update_en) begin
        if(actual_taken) begin
            if(pht[update_index]!=2'b11) pht[update_index] <= pht[update_index] + 1;
        end
        else begin
            if(pht[update_index]!=2'b00)
                pht[update_index] <= pht[update_index] - 1;
        end
    end
end

endmodule