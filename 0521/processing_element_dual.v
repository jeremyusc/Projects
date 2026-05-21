/*
 * Processing Element - True INT8/INT4 Dual Precision
 * Stores and uses quantized weights for both precisions
 * INT4: 4-bit × 4-bit = 8-bit result
 * INT8: 8-bit × 8-bit = 16-bit result
 */

module processing_element_dual_precision #(
    parameter WIDTH_INT8 = 8,
    parameter WIDTH_INT4 = 4,
    parameter WIDTH_ACCUM = 32
) (
    input  clk,
    input  rstn,
    
    // Control signals
    input  precision_mode,      // 0: INT8, 1: INT4
    input  compute_enable,
    input  reset_accum,
    input  load_weight,
    
    // INT8 precision inputs
    input  [WIDTH_INT8-1:0] weight_in_int8,
    input  [WIDTH_INT8-1:0] data_in_left_int8,
    input  [WIDTH_ACCUM-1:0] data_in_top_int8,
    
    // INT4 precision inputs (4-bit values)
    input  [WIDTH_INT4-1:0] weight_in_int4,
    input  [WIDTH_INT4-1:0] data_in_left_int4,
    input  [WIDTH_ACCUM-1:0] data_in_top_int4,
    
    // Data outputs
    output [WIDTH_INT8-1:0] data_out_right,
    output [WIDTH_ACCUM-1:0] data_out_down,
    output [WIDTH_ACCUM-1:0] accum_out,
    output valid_out
);

    // Storage for both precisions
    reg signed [WIDTH_INT8-1:0] weight_reg_int8;    // INT8 weight
    reg signed [WIDTH_INT4-1:0] weight_reg_int4;    // INT4 weight
    
    reg signed [WIDTH_INT8-1:0] input_reg_int8;     // INT8 input
    reg signed [WIDTH_INT4-1:0] input_reg_int4;     // INT4 input
    
    reg signed [WIDTH_ACCUM-1:0] accum_reg;         // Accumulator
    
    // Select inputs based on precision mode
    wire signed [WIDTH_INT8-1:0] weight_selected = 
        (precision_mode == 1'b0) ? weight_reg_int8 : {{4{weight_reg_int4[3]}}, weight_reg_int4};
    
    wire signed [WIDTH_INT8-1:0] input_selected = 
        (precision_mode == 1'b0) ? input_reg_int8 : {{4{input_reg_int4[3]}}, input_reg_int4};
    
    wire signed [WIDTH_ACCUM-1:0] partial_sum_selected =
        (precision_mode == 1'b0) ? data_in_top_int8 : data_in_top_int4;
    
    // MAC: Multiply & Accumulate
    wire signed [15:0] mult_result;         // Always 16-bit (8×8)
    wire signed [WIDTH_ACCUM-1:0] add_result;
    wire signed [WIDTH_ACCUM-1:0] accum_next;
    
    // Multiplier: Always computes, result selected by mode
    assign mult_result = weight_selected * input_selected;
    
    // Adder
    assign add_result = accum_reg + {{16{mult_result[15]}}, mult_result};
    
    // Saturation logic for both modes
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
            1'b1: begin  // INT4 mode
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
            weight_reg_int8 <= 8'h0;
            weight_reg_int4 <= 4'h0;
            input_reg_int8 <= 8'h0;
            input_reg_int4 <= 4'h0;
            accum_reg <= 32'h0;
        end else begin
            // Load both weight precisions
            if (load_weight) begin
                weight_reg_int8 <= weight_in_int8;
                weight_reg_int4 <= weight_in_int4;
            end
            
            // Store both input precisions
            if (compute_enable) begin
                input_reg_int8 <= data_in_left_int8;
                input_reg_int4 <= data_in_left_int4;
            end
            
            // Update accumulator
            if (reset_accum)
                accum_reg <= 32'h0;
            else if (compute_enable)
                accum_reg <= accum_next;
        end
    end
    
    // Data Forwarding
    // Always forward INT8 representation (extended from INT4 if needed)
    assign data_out_right = (precision_mode == 1'b0) ? 
        input_reg_int8 : {{4{input_reg_int4[3]}}, input_reg_int4};
    
    assign data_out_down = accum_reg;
    
    // Output interface
    assign accum_out = accum_reg;
    assign valid_out = compute_enable;

endmodule
