/*
 * 8x8 Systolic Array - Weight-Stationary, Dual Precision (INT8 / INT4)
 *
 * Changes vs previous version:
 *  - Instantiates processing_element_dual_precision (was: processing_element)
 *  - Adds separate INT8 and INT4 weight/input ports
 *  - Routes both precision lanes through the systolic fabric
 *  - Fixes illegal reg + assign mix on left_input (now a wire)
 *
 * Forwarding rule for INT4 lane between PEs:
 *  Each PE's data_out_right is 8-bit (in INT4 mode it is the sign-extended
 *  4-bit input). The next PE to the right consumes:
 *    - data_in_left_int8 = full 8 bits
 *    - data_in_left_int4 = lower 4 bits (= original INT4 value, since sign
 *                          extension preserves the low nibble exactly)
 */

module systolic_array_8x8 (
    input  clk,
    input  rstn,

    // Control
    input  precision_mode,           // 0: INT8, 1: INT4
    input  start_compute,
    input  load_weights,
    input  reset_all,

    // Weight inputs (broadcast / pre-loaded to each PE)
    input  [7:0] weight_in_int8 [0:7][0:7],
    input  [3:0] weight_in_int4 [0:7][0:7],

    // Activation inputs (leftmost column)
    input  [7:0] data_in_left_int8 [0:7],
    input  [3:0] data_in_left_int4 [0:7],

    // Outputs (bottom row accumulators)
    output [31:0] data_out_bottom [0:7],
    output valid_out,
    output busy,
    output [3:0] cycle_counter
);

    // ---------------- Interconnect wires ----------------
    // Horizontal data forwarding. Column index runs 0..8 (8 is right boundary)
    wire [7:0]  pe_data_right [0:7][0:8];

    // Vertical partial-sum forwarding. Row index runs 0..8 (8 is bottom pad)
    wire [31:0] pe_data_down  [0:8][0:7];

    // Per-PE accumulator readout
    wire [31:0] pe_accum_out  [0:7][0:7];

    // ---------------- Control ----------------
    reg  [3:0] cycle_reg;
    wire [3:0] cycle_cnt = cycle_reg;
    wire compute_en      = start_compute && (cycle_cnt < 8);

    assign busy          = start_compute;
    assign cycle_counter = cycle_cnt;

    // ---------------- PE grid ----------------
    genvar i, j;
    generate
        for (i = 0; i < 8; i = i + 1) begin : PE_ROW
            for (j = 0; j < 8; j = j + 1) begin : PE_COL

                // ----- Left input selection (boundary or neighbor) -----
                wire [7:0] left_int8;
                wire [3:0] left_int4;

                if (j == 0) begin : LEFT_BOUNDARY
                    assign left_int8 = data_in_left_int8[i];
                    assign left_int4 = data_in_left_int4[i];
                end else begin : LEFT_NEIGHBOR
                    // pe_data_right[i][j] is 8-bit; lower nibble == original INT4
                    assign left_int8 = pe_data_right[i][j];
                    assign left_int4 = pe_data_right[i][j][3:0];
                end

                // ----- Top input selection (boundary or neighbor) -----
                wire [31:0] top_psum;
                if (i == 0) begin : TOP_BOUNDARY
                    assign top_psum = 32'h0;
                end else begin : TOP_NEIGHBOR
                    assign top_psum = pe_data_down[i][j];
                end

                // ----- PE instance (dual precision) -----
                processing_element_dual_precision PE_inst (
                    .clk            (clk),
                    .rstn           (rstn),
                    .precision_mode (precision_mode),
                    .compute_enable (compute_en),
                    .reset_accum    (reset_all || (cycle_cnt == 4'd0)),
                    .load_weight    (load_weights),

                    // INT8 lane
                    .weight_in_int8    (weight_in_int8[i][j]),
                    .data_in_left_int8 (left_int8),
                    .data_in_top_int8  (top_psum),

                    // INT4 lane
                    .weight_in_int4    (weight_in_int4[i][j]),
                    .data_in_left_int4 (left_int4),
                    .data_in_top_int4  (top_psum),

                    // Forwarding outputs
                    .data_out_right (pe_data_right[i][j+1]),
                    .data_out_down  (pe_data_down[i+1][j]),

                    // Readout
                    .accum_out      (pe_accum_out[i][j]),
                    .valid_out      ()
                );
            end

            // Right-edge dangling wire (tie off for cleanliness)
            assign pe_data_right[i][8] = 8'h0;
        end

        // Bottom-row outputs
        for (j = 0; j < 8; j = j + 1) begin : OUTPUT_COL
            assign data_out_bottom[j] = pe_accum_out[7][j];
        end

        // Bottom padding (unused; tied off)
        for (j = 0; j < 8; j = j + 1) begin : BOTTOM_PAD
            assign pe_data_down[8][j] = 32'h0;
        end
    endgenerate

    // ---------------- Cycle counter ----------------
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            cycle_reg <= 4'h0;
        end else if (reset_all) begin
            cycle_reg <= 4'h0;
        end else if (start_compute && cycle_cnt < 4'd15) begin
            cycle_reg <= cycle_cnt + 4'd1;
        end
    end

    // Computation complete after 2N-1 = 15 cycles
    assign valid_out = (cycle_cnt == 4'd15) && start_compute;

endmodule
