/*
 * Testbench for Simplified Systolic Accelerator with DMA
 * Tests 3-state FSM: IDLE -> READ -> TRANSFER
 */

`timescale 1ns / 1ps

module tb_systolic_dma;

    // Clock and reset
    reg clk;
    reg rstn;
    
    // Control
    reg compute_start;
    reg [1:0] precision_mode;
    
    // External memory interface
    wire [15:0] ext_addr;
    wire ext_read_en;
    wire ext_write_en;
    reg  [31:0] ext_data_in;
    wire [31:0] ext_data_out;
    
    // Status
    wire data_ready;
    wire transfer_done;
    wire [3:0] dma_state;
    wire [3:0] cycles_out;
    wire computation_done;
    
    // External memory model
    reg [31:0] mem [0:255];
    
    integer i, j, idx;
    
    // Clock generation: 2ns period = 500MHz
    initial begin
        clk = 1'b0;
        forever #1 clk = ~clk;
    end
    
    // DUT instantiation
    systolic_accelerator_with_sram dut (
        .clk(clk),
        .rstn(rstn),
        .compute_start(compute_start),
        .precision_mode(precision_mode),
        .ext_addr(ext_addr),
        .ext_read_en(ext_read_en),
        .ext_write_en(ext_write_en),
        .ext_data_in(ext_data_in),
        .ext_data_out(ext_data_out),
        .data_ready(data_ready),
        .transfer_done(transfer_done),
        .dma_state(dma_state),
        .cycles_out(cycles_out),
        .computation_done(computation_done)
    );
    
    // External memory simulation
    always @(posedge clk) begin
        if (ext_read_en) begin
            ext_data_in <= mem[ext_addr];
            $display("[MEM_READ] Addr=0x%04h, Data=0x%08h", ext_addr, mem[ext_addr]);
        end
        
        if (ext_write_en) begin
            mem[ext_addr] <= ext_data_out;
            $display("[MEM_WRITE] Addr=0x%04h, Data=0x%08h", ext_addr, ext_data_out);
        end
    end
    
    // State names for display
    function string state_name(input [3:0] state);
        case (state)
            2'b00: return "IDLE";
            2'b01: return "READ";
            2'b10: return "TRANSFER";
            default: return "UNKNOWN";
        endcase
    endfunction
    
    // Test stimulus
    initial begin
        // Initialize
        rstn = 1'b0;
        compute_start = 1'b0;
        precision_mode = 2'b00;  // INT8
        ext_data_in = 32'h0;
        
        // Initialize external memory with test data
        $display("Initializing test data in external memory...");
        
        // Input vector (words 0-1): 8 values (2 words for 8 INT8 values)
        mem[0] = {8'd2, 8'd1, 8'd0, 8'd0};
        mem[1] = {8'd4, 8'd3, 8'd0, 8'd0};
        
        // Weight matrix (words 2-17): 64 values (16 words = 64 INT8 values)
        idx = 2;
        for (i = 0; i < 8; i = i + 1) begin
            for (j = 0; j < 8; j = j + 2) begin
                mem[idx] = {8'(i*8+j+2), 8'(i*8+j+1), 8'd0, 8'd0};
                idx = idx + 1;
            end
        end
        
        repeat (5) @(posedge clk);
        rstn = 1'b1;
        
        $display("\n=== Starting Systolic Array Test ===");
        $display("Time: %0t", $time);
        
        // Start computation
        @(posedge clk);
        compute_start = 1'b1;
        
        $display("\n[TIME %0t] Compute start signal asserted", $time);
        $display("Expected FSM sequence: IDLE -> READ -> TRANSFER");
        
        @(posedge clk);
        compute_start = 1'b0;
        
        // Monitor FSM states
        repeat (300) @(posedge clk) begin
            if (data_ready) begin
                $display("[TIME %0t] ✓ Data ready (DMA READ completed)", $time);
            end
            if (transfer_done) begin
                $display("[TIME %0t] ✓ Transfer done (DMA TRANSFER completed)", $time);
            end
            if (computation_done) begin
                $display("[TIME %0t] ✓ Computation done", $time);
            end
        end
        
        // Final status
        $display("\n=== Final Status ===");
        $display("DMA State: %s", state_name(dma_state));
        $display("Data Ready: %b", data_ready);
        $display("Transfer Done: %b", transfer_done);
        $display("Computation Done: %b", computation_done);
        $display("Systolic Cycles: %0d", cycles_out);
        
        $display("\nTest completed at time %0t", $time);
        $finish;
    end
    
    // Monitor FSM state transitions
    always @(posedge clk) begin
        case (dma_state)
            2'b00: $display("[FSM] State: IDLE");
            2'b01: $display("[FSM] State: READ (reading weights and inputs)");
            2'b10: $display("[FSM] State: TRANSFER (writing results)");
        endcase
    end
    
    // Monitor compute signals
    always @(posedge clk) begin
        if (cycles_out > 0 && cycles_out <= 15) begin
            $display("[COMPUTE] Systolic cycle: %0d", cycles_out);
        end
    end

endmodule
