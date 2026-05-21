/*
 * Systolic Accelerator Top-Level with Integrated SRAM
 * Complete system with unified SRAM and DMA controller
 */

module systolic_accelerator_with_sram (
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
    output computation_done
);

    // ========== INTERNAL SIGNALS ==========
    
    // SRAM signals
    wire [15:0] sram_addr;
    wire sram_write_en, sram_read_en;
    wire [31:0] sram_data_out;
    wire [31:0] sram_data_in;
    wire input_ready, weight_ready, output_valid;
    
    // PE Array signals
    wire [7:0] weight_matrix [0:7][0:7];
    wire [7:0] input_vector [0:7];
    wire [31:0] output_vector [0:7];
    wire [3:0] cycle_count;
    wire array_valid_out, array_busy;
    
    // ========== UNIFIED SRAM ==========
    unified_sram sram_inst (
        .clk(clk),
        .rstn(rstn),
        
        // Port A: DMA Interface (read/write)
        .addr_a(sram_addr),
        .write_en_a(sram_write_en),
        .read_en_a(sram_read_en),
        .data_in_a(sram_data_in),
        .data_out_a(sram_data_out),
        
        // Port B: PE Array Interface (read only)
        .addr_b(16'h0),  // TODO: Connect to PE array address generator
        .read_en_b(1'b1),
        .data_out_b(),
        
        // Status
        .input_ready(input_ready),
        .weight_ready(weight_ready),
        .output_valid(output_valid)
    );
    
    // ========== DMA CONTROLLER WITH SRAM ==========
    dma_with_sram dma_inst (
        .clk(clk),
        .rstn(rstn),
        
        // External memory
        .compute_start(compute_start),
        .precision_mode(precision_mode),
        .ext_addr(ext_addr),
        .ext_read_en(ext_read_en),
        .ext_write_en(ext_write_en),
        .ext_data_in(ext_data_in),
        .ext_data_out(ext_data_out),
        
        // SRAM interface
        .sram_addr(sram_addr),
        .sram_write_en(sram_write_en),
        .sram_read_en(sram_read_en),
        .sram_data_out(sram_data_out),
        .sram_data_in(sram_data_in),
        
        // Status
        .data_ready(data_ready),
        .transfer_done(transfer_done),
        .dma_state(dma_state)
    );
    
    // ========== SRAM TO PE ARRAY INTERFACE ==========
    // Extract Input Vector from SRAM
    // SRAM Layout:
    // 0x00: [Input[3:0]]
    // 0x01: [Input[7:4]]
    wire [31:0] input_word_0 = sram_data_out;  // Would read from SRAM addr 0x0000
    wire [31:0] input_word_1;                   // Would read from SRAM addr 0x0001
    
    // TODO: Implement proper SRAM read for input_vector[0:7]
    // assign input_vector[0] = input_word_0[7:0];
    // assign input_vector[1] = input_word_0[15:8];
    // ...etc
    
    // Extract Weight Matrix from SRAM
    // SRAM Layout:
    // 0x02-0x11: [Weight[8][8]]
    // TODO: Implement proper SRAM read for weight_matrix[8][8]
    
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
    
    // ========== 8×8 SYSTOLIC ARRAY ==========
    systolic_array_8x8 systolic_inst (
        .clk(clk),
        .rstn(rstn),
        .precision_mode(precision_mode[0]),
        .start_compute(data_ready),
        .load_weights(weight_ready),
        .reset_all(compute_start),
        .weight_in(weight_matrix),
        .data_in_left(input_vector),
        .data_out_bottom(output_vector),
        .valid_out(array_valid_out),
        .busy(array_busy),
        .cycle_counter(cycle_count)
    );
    
    // Connect outputs
    assign cycles_out = cycle_count;

endmodule
