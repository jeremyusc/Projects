/*
 * DMA Controller with Unified SRAM - Corrected Version
 *
 * Fixes vs previous version:
 *   1. Routes input -> input partition (0x0000+), weight -> weight partition
 *      (0x4000+), output -> output partition (0x8000+). Previously everything
 *      landed in input_sram because sram_addr was just word_counter.
 *   2. INT4 mode now reads 9 words (1 input + 8 weight = 64 INT4 weights),
 *      not 5 words. Previous 4 weight words could only hold 32 INT4 weights.
 *   3. dma_write_start / dma_write_complete are driven from a single
 *      sequential block (no more multi-driver conflict).
 *   4. dma_state is driven by always @(*) instead of mixing assign with reg.
 *   5. Read pipeline correctly handles the external memory's 1-cycle read
 *      latency. Per word k:
 *         cycle N:   present ext_addr = k    (combinational)
 *         cycle N+1: ext_data_in = mem[k]    (registered by memory model)
 *                    write to SRAM at addr_for(k) with sram_data_in = ext_data_in
 *      Implemented with a one-cycle delayed sram_write_cnt + sram_write_valid.
 *   6. (See top-level wrapper fix) SRAM read_en_a now connects to sram_read_en
 *      so TRANSFER state can actually read output partition.
 *
 * Memory layout assumptions:
 *   External memory:
 *     INT8 mode: 0x0000-0x0001 = input (2 words), 0x0002-0x0011 = weight (16 words)
 *     INT4 mode: 0x0020       = input (1 word),  0x0021-0x0028 = weight (8 words)
 *     Output:    0x0100-0x0107 (8 words)
 *
 *   Internal SRAM (partition selected by addr[15:14]):
 *     2'b00 -> input  partition, base 0x0000
 *     2'b01 -> weight partition, base 0x4000
 *     2'b10 -> output partition, base 0x8000
 */

module dma_with_sram_v2 (
    input  clk,
    input  rstn,

    input  compute_start,
    input  [1:0] precision_mode,

    // External memory interface
    output reg [15:0] ext_addr,
    output reg ext_read_en,
    output reg ext_write_en,
    input  [31:0] ext_data_in,
    output reg [31:0] ext_data_out,

    // Internal SRAM interface (port A)
    output reg [15:0] sram_addr,
    output reg sram_write_en,
    output reg sram_read_en,
    input  [31:0] sram_data_out,
    output reg [31:0] sram_data_in,

    // Precision-mode handshake to SRAM
    output reg dma_write_start,     // one-cycle pulse: new transfer beginning
    output reg dma_write_complete,  // one-cycle pulse: all data written to SRAM

    // Status
    output reg data_ready,
    output reg transfer_done,
    output reg [3:0] dma_state
);

    // ========== ADDRESS MAP CONSTANTS ==========
    localparam [15:0] SRAM_INPUT_BASE  = 16'h0000;
    localparam [15:0] SRAM_WEIGHT_BASE = 16'h4000;
    localparam [15:0] SRAM_OUTPUT_BASE = 16'h8000;

    localparam [15:0] EXT_INT8_BASE = 16'h0000;
    localparam [15:0] EXT_INT4_BASE = 16'h0020;
    localparam [15:0] EXT_OUT_BASE  = 16'h0100;

    // Per-precision word counts:
    //   INT8: 8 inputs / 4-per-word = 2 input words
    //         64 weights / 4-per-word = 16 weight words -> 18 total
    //   INT4: 8 inputs / 8-per-word = 1 input word
    //         64 weights / 8-per-word = 8 weight words  -> 9 total
    wire [7:0]  total_read_words = (precision_mode == 2'b00) ? 8'd18 : 8'd9;
    wire [7:0]  input_word_count = (precision_mode == 2'b00) ? 8'd2  : 8'd1;
    wire [15:0] ext_read_base    = (precision_mode == 2'b00) ? EXT_INT8_BASE
                                                             : EXT_INT4_BASE;

    // ========== FSM ==========
    localparam [2:0] S_IDLE     = 3'd0;
    localparam [2:0] S_READ     = 3'd1; // issuing ext addresses, writing SRAM with 1-cycle delay
    localparam [2:0] S_READ_END = 3'd2; // drain the last in-flight word
    localparam [2:0] S_TRANSFER = 3'd3; // output SRAM -> ext memory
    localparam [2:0] S_DONE     = 3'd4;

    reg [2:0] state, next_state;

    // Read pipeline counters
    reg [7:0] read_addr_cnt;   // address being issued to ext memory this cycle
    reg [7:0] sram_write_cnt;  // address being written to SRAM this cycle (= read_addr_cnt delayed 1)
    reg       sram_write_valid;// gates sram_write_en; goes high one cycle after first read

    // Transfer counter (SRAM read is combinational, no pipeline needed)
    reg [7:0] xfer_cnt;

    // ========== STATE REGISTER ==========
    always @(posedge clk or negedge rstn) begin
        if (!rstn) state <= S_IDLE;
        else       state <= next_state;
    end

    // ========== NEXT STATE LOGIC ==========
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:     if (compute_start)                         next_state = S_READ;
            S_READ:     if (read_addr_cnt == total_read_words-1)   next_state = S_READ_END;
            S_READ_END:                                            next_state = S_TRANSFER;
            S_TRANSFER: if (xfer_cnt == 8'd7)                      next_state = S_DONE;
            S_DONE:                                                next_state = S_IDLE;
            default:                                               next_state = S_IDLE;
        endcase
    end

    // ========== READ PIPELINE COUNTERS ==========
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            read_addr_cnt    <= 8'h0;
            sram_write_cnt   <= 8'h0;
            sram_write_valid <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    read_addr_cnt    <= 8'h0;
                    sram_write_cnt   <= 8'h0;
                    sram_write_valid <= 1'b0;
                end
                S_READ: begin
                    if (read_addr_cnt < total_read_words - 1)
                        read_addr_cnt <= read_addr_cnt + 8'd1;
                    sram_write_cnt   <= read_addr_cnt;  // delay by 1 cycle
                    sram_write_valid <= 1'b1;
                end
                S_READ_END: begin
                    // Drain the last in-flight word, then stop
                    sram_write_cnt   <= read_addr_cnt;
                    sram_write_valid <= 1'b1;
                end
                default: begin
                    sram_write_valid <= 1'b0;
                end
            endcase
        end
    end

    // ========== TRANSFER COUNTER ==========
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            xfer_cnt <= 8'h0;
        end else begin
            case (state)
                S_IDLE, S_READ, S_READ_END: xfer_cnt <= 8'h0;
                S_TRANSFER: if (xfer_cnt < 8'd7) xfer_cnt <= xfer_cnt + 8'd1;
                default: ;
            endcase
        end
    end

    // ========== STATUS / HANDSHAKE FLAGS ==========
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            data_ready         <= 1'b0;
            transfer_done      <= 1'b0;
            dma_write_start    <= 1'b0;
            dma_write_complete <= 1'b0;
        end else begin
            // One-cycle pulses default to 0
            dma_write_start    <= 1'b0;
            dma_write_complete <= 1'b0;

            // Pulse when entering READ (tell SRAM: new precision-mode session)
            if (state == S_IDLE && next_state == S_READ)
                dma_write_start <= 1'b1;

            // Pulse when SRAM has received all data
            if (state == S_READ_END && next_state == S_TRANSFER) begin
                dma_write_complete <= 1'b1;
                data_ready         <= 1'b1;
            end

            // Latch transfer_done when leaving TRANSFER
            if (state == S_TRANSFER && next_state == S_DONE)
                transfer_done <= 1'b1;

            // Reset latched flags on return to IDLE
            if (state == S_DONE && next_state == S_IDLE) begin
                data_ready    <= 1'b0;
                transfer_done <= 1'b0;
            end
        end
    end

    // ========== COMBINATIONAL OUTPUTS ==========
    always @(*) begin
        // Default all outputs (safe values)
        ext_addr      = 16'h0;
        ext_read_en   = 1'b0;
        ext_write_en  = 1'b0;
        ext_data_out  = 32'h0;
        sram_addr     = 16'h0;
        sram_write_en = 1'b0;
        sram_read_en  = 1'b0;
        sram_data_in  = 32'h0;

        case (state)
            S_READ: begin
                // Issue next external address
                ext_read_en = 1'b1;
                ext_addr    = ext_read_base + read_addr_cnt;

                // Route delayed counter to the correct SRAM partition
                if (sram_write_cnt < input_word_count)
                    sram_addr = SRAM_INPUT_BASE + sram_write_cnt;
                else
                    sram_addr = SRAM_WEIGHT_BASE + (sram_write_cnt - input_word_count);

                sram_write_en = sram_write_valid;
                sram_data_in  = ext_data_in;  // already registered by memory model
            end

            S_READ_END: begin
                // Drain: write the last word, no more ext reads
                if (sram_write_cnt < input_word_count)
                    sram_addr = SRAM_INPUT_BASE + sram_write_cnt;
                else
                    sram_addr = SRAM_WEIGHT_BASE + (sram_write_cnt - input_word_count);

                sram_write_en = sram_write_valid;
                sram_data_in  = ext_data_in;
            end

            S_TRANSFER: begin
                // SRAM read is combinational (assign-based), so no pipeline needed
                sram_read_en = 1'b1;
                sram_addr    = SRAM_OUTPUT_BASE + xfer_cnt;
                ext_addr     = EXT_OUT_BASE + xfer_cnt;
                ext_data_out = sram_data_out;
                ext_write_en = 1'b1;
            end

            default: ; // IDLE, DONE: outputs stay at defaults
        endcase
    end

    // ========== STATE EXPORT ==========
    always @(*) dma_state = {1'b0, state};

endmodule
