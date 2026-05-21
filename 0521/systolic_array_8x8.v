/*
 * 8×8 Systolic Array - Weight-Stationary Configuration
 * Complete PE array with interconnect and control logic
 * TSMC 28nm LP, 500MHz
 */

module systolic_array_8x8 (
    input  clk,
    input  rstn,
    
    // Control signals
    input  precision_mode,           // 0: INT8, 1: INT4
    input  start_compute,            // Start new computation tile
    input  load_weights,             // Load weight matrix
    input  reset_all,                // Reset all accumulators
    
    // Weight input (broadcast to all PEs)
    input  [7:0] weight_in [0:7][0:7],  // 8×8 weight matrix (INT8)
    
    // Data input (from Input SRAM)
    input  [7:0] data_in_left [0:7],   // 8 inputs for leftmost column
    
    // Data output (to Output SRAM)
    output [31:0] data_out_bottom [0:7], // 8 partial sums from bottom row
    output valid_out,
    output busy,
    output [3:0] cycle_counter
);

    // PE Grid - 8x8 array of processing elements
    wire [7:0] pe_data_right  [0:7][0:8];   // Horizontal data flow
    wire [31:0] pe_data_down  [0:8][0:7];   // Vertical data flow
    wire [31:0] pe_accum_out  [0:7][0:7];   // Accumulator outputs
    
    // Control Signals
    wire [3:0] cycle_cnt;
    wire compute_en;
    reg  [3:0] cycle_reg;
    
    assign cycle_cnt = cycle_reg;
    assign busy = start_compute;
    assign cycle_counter = cycle_cnt;
    assign compute_en = start_compute && (cycle_cnt < 8);
    
    // PE Array Generation using generate blocks
    genvar i, j;
    generate
        for (i = 0; i < 8; i = i + 1) begin : PE_ROW
            for (j = 0; j < 8; j = j + 1) begin : PE_COL
                
                // Determine input from left (boundary or adjacent PE)
                wire [7:0] left_input;
                if (j == 0) begin
                    assign left_input = data_in_left[i];
                end else begin
                    assign left_input = pe_data_right[i][j];
                end
                
                // Determine input from top (boundary padding or adjacent PE)
                wire [31:0] top_input;
                if (i == 0) begin
                    assign top_input = 32'h0;
                end else begin
                    assign top_input = pe_data_down[i][j];
                end
                
                // Instantiate PE
                processing_element PE_inst (
                    .clk(clk),
                    .rstn(rstn),
                    .precision_mode(precision_mode),
                    .compute_enable(compute_en),
                    .reset_accum(reset_all || (cycle_cnt == 0)),
                    .load_weight(load_weights),
                    .weight_in(weight_in[i][j]),
                    .data_in_left(left_input),
                    .data_in_top(top_input),
                    .data_out_right(pe_data_right[i][j+1]),
                    .data_out_down(pe_data_down[i+1][j]),
                    .accum_out(pe_accum_out[i][j]),
                    .valid_out()
                );
            end
            
            // Boundary: right edge padding
            assign pe_data_right[i][8] = 8'h0;
        end
        
        // Boundary: bottom row outputs
        for (j = 0; j < 8; j = j + 1) begin : OUTPUT_COL
            assign data_out_bottom[j] = pe_accum_out[7][j];
        end
        
        // Boundary: bottom padding (zeros)
        for (j = 0; j < 8; j = j + 1) begin : BOTTOM_PAD
            assign pe_data_down[8][j] = 32'h0;
        end
    endgenerate
    
    // Systolic Timing Control
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            cycle_reg <= 4'h0;
        end else if (reset_all) begin
            cycle_reg <= 4'h0;
        end else if (start_compute && cycle_cnt < 15) begin
            cycle_reg <= cycle_cnt + 1;
        end
    end
    
    // Valid output when computation complete (2N-1 = 15 cycles for N=8)
    assign valid_out = (cycle_cnt == 15) && start_compute;

endmodule
