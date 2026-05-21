/*
 * Systolic Accelerator Top-Level - Dual Precision Wiring
 *
 * Changes vs previous version:
 *  - Adds INT4 weight and input vector wires
 *  - Connects them to the dual-precision systolic_array_8x8
 *  - Leaves the SRAM -> {weight_matrix, input_vector} address generation
 *    as TODO (that is the next fix in our list).
 */

module systolic_accelerator_with_sram_v2 (
    // Clock and Reset
    input  clk,
    input  rstn,

    // Control
    input  compute_start,
    input  [1:0] precision_mode,

    // External Memory Interface
    output [15:0] ext_addr,
    output ext_read_en,
    output ext_write_en,
    input  [31:0] ext_data_in,
    output [31:0] ext_data_out,

    // Status outputs
    output [3:0] dma_state,
    output [3:0] cycles_out,
    output data_ready,
    output transfer_done,
    output computation_done,

    // Precision mode visibility
    output [1:0] sram_precision_mode,
    output sram_precision_valid,
    output precision_mismatch_error
);

    // ========== SRAM SIGNALS ==========
    wire [15:0] sram_addr;
    wire sram_write_en, sram_read_en;
    wire [31:0] sram_data_out;
    wire [31:0] sram_data_in;
    wire input_ready, weight_ready, output_valid;

    // Precision mode coordination
    wire dma_write_start;
    wire dma_write_complete;
    wire precision_valid_sram;
    wire precision_mismatch_sram;

    // ========== PE ARRAY SIGNALS (dual precision) ==========
    // INT8 lane
    wire [7:0]  weight_matrix_int8 [0:7][0:7];
    wire [7:0]  input_vector_int8  [0:7];
    // INT4 lane
    wire [3:0]  weight_matrix_int4 [0:7][0:7];
    wire [3:0]  input_vector_int4  [0:7];

    wire [31:0] output_vector [0:7];
    wire [3:0]  cycle_count;
    wire array_valid_out, array_busy;

    // ========== UNIFIED SRAM ==========
    unified_sram sram_inst (
        .clk(clk),
        .rstn(rstn),

        // Port A: DMA
        .addr_a(sram_addr),
        .write_en_a(sram_write_en),
        .read_en_a(sram_read_en),  // FIX: was 1'b0; needed for TRANSFER state
        .data_in_a(sram_data_in),
        .data_out_a(sram_data_out),

        // Port B: PE Array (placeholder)
        .addr_b(16'h0),
        .read_en_b(1'b1),
        .data_out_b(),

        // Precision
        .precision_mode_in(precision_mode),
        .dma_write_start(dma_write_start),
        .dma_write_complete(dma_write_complete),
        .precision_mode_sram(sram_precision_mode),
        .precision_valid(precision_valid_sram),
        .precision_mismatch(precision_mismatch_sram),

        // Status
        .input_ready(input_ready),
        .weight_ready(weight_ready),
        .output_valid(output_valid)
    );

    // ========== DMA CONTROLLER ==========
    dma_with_sram_v2 dma_inst (
        .clk(clk),
        .rstn(rstn),
        .compute_start(compute_start),
        .precision_mode(precision_mode),
        .ext_addr(ext_addr),
        .ext_read_en(ext_read_en),
        .ext_write_en(ext_write_en),
        .ext_data_in(ext_data_in),
        .ext_data_out(ext_data_out),
        .sram_addr(sram_addr),
        .sram_write_en(sram_write_en),
        .sram_read_en(sram_read_en),
        .sram_data_out(sram_data_out),
        .sram_data_in(sram_data_in),
        .dma_write_start(dma_write_start),
        .dma_write_complete(dma_write_complete),
        .data_ready(data_ready),
        .transfer_done(transfer_done),
        .dma_state(dma_state)
    );

    // ========== READY-TO-COMPUTE GATE ==========
    wire sram_valid_for_compute =
        data_ready && precision_valid_sram && ~precision_mismatch_sram;

    // ========== SRAM -> PE ARRAY (TODO: address generator) ==========
    // TODO (next fix): replace these placeholders with real reads out of
    // unified_sram Port B. For now they are tied off so the design elaborates
    // cleanly; the array will run on zeros until the address generator is in.
    genvar gi, gj;
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin : INPUT_TIE
            assign input_vector_int8[gi] = 8'h0;
            assign input_vector_int4[gi] = 4'h0;
            for (gj = 0; gj < 8; gj = gj + 1) begin : WEIGHT_TIE
                assign weight_matrix_int8[gi][gj] = 8'h0;
                assign weight_matrix_int4[gi][gj] = 4'h0;
            end
        end
    endgenerate

    // ========== SYSTEM CONTROLLER ==========
    system_controller sys_ctrl_inst (
        .clk(clk),
        .rstn(rstn),
        .precision_request(precision_mode),
        .compute_start(compute_start),
        .num_layers(4'h4),
        .precision_mode(),
        .array_enable(),
        .memory_enable(),
        .clock_enable(),
        .vdd_level(),
        .memory_retention(),
        .current_layer(),
        .power_state(),
        .computation_done(computation_done)
    );

    // ========== 8x8 SYSTOLIC ARRAY (dual precision) ==========
    systolic_array_8x8 systolic_inst (
        .clk(clk),
        .rstn(rstn),
        .precision_mode(precision_mode[0]),
        .start_compute(sram_valid_for_compute),
        .load_weights(weight_ready),
        .reset_all(compute_start),

        // INT8 lane
        .weight_in_int8(weight_matrix_int8),
        .data_in_left_int8(input_vector_int8),

        // INT4 lane
        .weight_in_int4(weight_matrix_int4),
        .data_in_left_int4(input_vector_int4),

        // Outputs
        .data_out_bottom(output_vector),
        .valid_out(array_valid_out),
        .busy(array_busy),
        .cycle_counter(cycle_count)
    );

    // ========== OUTPUT ASSIGNMENTS ==========
    assign cycles_out               = cycle_count;
    assign sram_precision_valid     = precision_valid_sram;
    assign precision_mismatch_error = precision_mismatch_sram;

endmodule
