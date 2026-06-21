module BTB#(
    parameter DATA_WIDTH = 32, 
    parameter ADDR = 10,
    parameter BTB_ENTRY = 16
)(
    input clk,rst,
    input [ADDR-1:0] current_pc,
    output reg [ADDR-1:0] target_pc,
    output reg btb_hit,

    ////update branch target
    input update_en,
    input [ADDR-1:0] update_pc,
    input [ADDR-1:0] update_target
);
localparam INDEX_BITS = $clog2(BTB_ENTRY);
reg valid [0:BTB_ENTRY-1];

////lookup table
reg [ADDR-1:0] branch_buffer [0:BTB_ENTRY-1];
reg [ADDR-1:0] target_buffer [0:BTB_ENTRY-1];
wire [INDEX_BITS-1:0] lookup_index = current_pc[INDEX_BITS+1:2];
always @(*) begin
    if(valid[lookup_index] && current_pc==branch_buffer[lookup_index]) begin
        btb_hit = 1;
        target_pc = target_buffer[lookup_index];
    end else begin
        btb_hit = 0;
        target_pc = 0; 
    end
end

///update
integer i;
wire [INDEX_BITS-1:0] index = update_pc[INDEX_BITS+1:2];
always @(posedge clk) begin
    if(rst) begin
        for(i=0;i<BTB_ENTRY;i=i+1)
            valid[i] <= 1'b0;
    end
    else if(update_en) begin
       branch_buffer[index] <= update_pc;
       target_buffer[index] <= update_target; 
       valid[index] <= 1'b1;
    end
end


endmodule