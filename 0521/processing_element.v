/*
 * Processing Element (PE) - Weight-Stationary Systolic Array
 * Single MAC unit with INT8/INT4 dual-mode precision
 * TSMC 28nm LP, 0.9V, 500MHz
 */

module processing_element #(
    parameter WIDTH_INT8 = 8,
    parameter WIDTH_INT4 = 4,
    parameter WIDTH_ACCUM = 32
) (
    // Clock and reset
    input  clk,
    input  rstn,
    
    // Control signals
    input  precision_mode,      // 0: INT8, 1: INT4
    input  compute_enable,      // Start MAC operation
    input  reset_accum,         // Reset accumulator
    input  load_weight,         // Load weight to register
    
    // Data inputs
    input  [WIDTH_INT8-1:0] weight_in,      // Weight input (INT8)
    input  [WIDTH_INT8-1:0] data_in_left,   // Data from left PE
    input  [WIDTH_ACCUM-1:0] data_in_top,   // Partial sum from above PE
    
    // Data outputs
    output [WIDTH_INT8-1:0] data_out_right, // Forward to right PE
    output [WIDTH_ACCUM-1:0] data_out_down, // Forward to bottom PE
    
    // Accumulator read (for output SRAM)
    output [WIDTH_ACCUM-1:0] accum_out,
    output valid_out
);

    // Internal Registers
    reg signed [WIDTH_INT8-1:0] weight_reg;     // Weight register (locked)
    reg signed [WIDTH_INT8-1:0] input_reg;      // Input register
    reg signed [WIDTH_ACCUM-1:0] accum_reg;     // 32-bit accumulator
    
    // MAC Unit: Multiply & Accumulate
    wire signed [15:0] mult_result;              // 8×8 → 16-bit
    wire signed [WIDTH_ACCUM-1:0] add_result;    // Adder output
    wire signed [WIDTH_ACCUM-1:0] accum_next;    // Next accumulator value
    
    // Multiplier (always computes)
    assign mult_result = weight_reg * input_reg;
    
    // Adder: accumulator + product
    assign add_result = accum_reg + {{16{mult_result[15]}}, mult_result};
    
    // Saturation logic (INT8: [-128,127], INT4: [-8,7])
    wire signed [WIDTH_ACCUM-1:0] saturated;
    
    always @(*) begin
        case (precision_mode)
            1'b0: begin  // INT8 mode
                if (add_result > 32'sd127)
                    saturated = 32'sd127;
                else if (add_result < -32'sd128)
                    saturated = -32'sd128;
                else
                    saturated = add_result;
            end
            1'b1: begin  // INT4 mode (lower precision)
                if (add_result > 32'sd7)
                    saturated = 32'sd7;
                else if (add_result < -32'sd8)
                    saturated = -32'sd8;
                else
                    saturated = add_result;
            end
            default: saturated = add_result;
        endcase
    end
    
    assign accum_next = saturated;
    
    // Pipeline Stage
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            weight_reg <= 8'h0;
            input_reg <= 8'h0;
            accum_reg <= 32'h0;
        end else begin
            // Load weight (weight-stationary: once per tile)
            if (load_weight)
                weight_reg <= weight_in;
            
            // Store input from left PE
            if (compute_enable)
                input_reg <= data_in_left;
            
            // Update accumulator
            if (reset_accum)
                accum_reg <= 32'h0;
            else if (compute_enable)
                accum_reg <= accum_next;
        end
    end
    
    // Data Forwarding (Systolic Dataflow)
    // Send input right to next PE
    assign data_out_right = input_reg;
    
    // Send accumulator down to PE below
    assign data_out_down = accum_reg;
    
    // Output interface
    assign accum_out = accum_reg;
    assign valid_out = compute_enable;

endmodule
