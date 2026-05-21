/*
 * DMA Controller - Integrated with Unified SRAM
 * Transfers data from external memory to internal SRAM partitions
 */

module dma_with_sram (
    input  clk,
    input  rstn,
    
    // External memory interface
    input  compute_start,
    input  [1:0] precision_mode,    // 0: INT8, 1: INT4
    
    output reg [15:0] ext_addr,
    output reg ext_read_en,
    output reg ext_write_en,
    input  [31:0] ext_data_in,
    output reg [31:0] ext_data_out,
    
    // Internal SRAM interface
    output reg [15:0] sram_addr,
    output reg sram_write_en,
    output reg sram_read_en,
    input  [31:0] sram_data_out,
    output reg [31:0] sram_data_in,
    
    // Status signals
    output reg data_ready,
    output reg transfer_done,
    output reg [3:0] dma_state
);

    // FSM States
    localparam IDLE = 2'b00;
    localparam READ = 2'b01;
    localparam TRANSFER = 2'b10;
    
    reg [1:0] state;
    reg [1:0] next_state;
    reg [7:0] word_counter;
    
    // ========== STATE MACHINE ==========
    
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= IDLE;
            word_counter <= 8'h0;
            data_ready <= 1'b0;
            transfer_done <= 1'b0;
        end else begin
            state <= next_state;
            
            case (state)
                IDLE: begin
                    word_counter <= 8'h0;
                    data_ready <= 1'b0;
                    transfer_done <= 1'b0;
                end
                
                READ: begin
                    if (precision_mode == 1'b0) begin  // INT8
                        if (word_counter < 18)
                            word_counter <= word_counter + 1;
                        if (word_counter == 17)
                            data_ready <= 1'b1;
                    end else begin  // INT4
                        if (word_counter < 5)
                            word_counter <= word_counter + 1;
                        if (word_counter == 4)
                            data_ready <= 1'b1;
                    end
                end
                
                TRANSFER: begin
                    if (word_counter < 8)
                        word_counter <= word_counter + 1;
                    if (word_counter == 7)
                        transfer_done <= 1'b1;
                end
            endcase
        end
    end
    
    // ========== NEXT STATE LOGIC ==========
    
    always @(*) begin
        next_state = state;
        ext_read_en = 1'b0;
        ext_write_en = 1'b0;
        ext_addr = 16'h0;
        ext_data_out = 32'h0;
        sram_write_en = 1'b0;
        sram_read_en = 1'b0;
        sram_addr = 16'h0;
        sram_data_in = 32'h0;
        
        case (state)
            IDLE: begin
                if (compute_start)
                    next_state = READ;
            end
            
            READ: begin
                // Read from external memory, write to SRAM
                ext_read_en = 1'b1;
                sram_write_en = 1'b1;
                
                if (precision_mode == 1'b0) begin  // INT8
                    // Read from ext memory 0x00-0x11
                    ext_addr = word_counter;
                    // Write to SRAM: Input(0x00-0x01) + Weight(0x02-0x11)
                    sram_addr = word_counter;  // Maps directly
                    sram_data_in = ext_data_in;
                    
                    if (word_counter == 17)
                        next_state = TRANSFER;
                end else begin  // INT4
                    // Read from ext memory 0x20-0x24
                    ext_addr = 16'h20 + word_counter;
                    // Write to SRAM: Input(0x00) + Weight(0x01-0x04)
                    sram_addr = word_counter;
                    sram_data_in = ext_data_in;
                    
                    if (word_counter == 4)
                        next_state = TRANSFER;
                end
            end
            
            TRANSFER: begin
                // Read from Output SRAM, write to external memory
                ext_write_en = 1'b1;
                sram_read_en = 1'b1;
                
                // Read from Output SRAM (0x300-0x307)
                sram_addr = 16'h0300 + word_counter;
                
                // Write to external memory (0x100-0x107)
                ext_addr = 16'h0100 + word_counter;
                ext_data_out = sram_data_out;
                
                if (word_counter == 7)
                    next_state = IDLE;
            end
        endcase
    end
    
    // Status output
    assign dma_state = {2'b00, state};

endmodule
