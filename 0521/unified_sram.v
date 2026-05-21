/*
 * Unified SRAM Module with Three Partitions
 * Input SRAM (256 KB), Weight SRAM (512 KB), Output SRAM (256 KB)
 * Dual-port design for simultaneous read/write
 */

module unified_sram (
    input  clk,
    input  rstn,
    
    // Port A: Write Port (for DMA input)
    input  [15:0] addr_a,           // Address: 0x000-0x5FF
    input  write_en_a,              // Write enable
    input  read_en_a,               // Read enable (for verification)
    input  [31:0] data_in_a,        // Write data (32-bit)
    output [31:0] data_out_a,       // Read data
    
    // Port B: Read Port (for PE Array)
    input  [15:0] addr_b,
    input  read_en_b,
    output [31:0] data_out_b,
    
    // Status signals
    output reg input_ready,
    output reg weight_ready,
    output reg output_valid
);

    // ========== MEMORY PARTITIONS ==========
    // Input SRAM: 256 words × 32-bit (0x000-0x0FF)
    reg [31:0] input_sram [0:255];
    
    // Weight SRAM: 512 words × 32-bit (0x100-0x2FF)
    reg [31:0] weight_sram [0:511];
    
    // Output SRAM: 256 words × 32-bit (0x300-0x3FF)
    reg [31:0] output_sram [0:255];
    
    // ========== ADDRESS DECODING ==========
    wire [1:0] partition_a = addr_a[15:14];
    wire [1:0] partition_b = addr_b[15:14];
    
    wire [7:0] input_addr_a = addr_a[7:0];
    wire [8:0] weight_addr_a = addr_a[8:0];
    wire [7:0] output_addr_a = addr_a[7:0];
    
    wire [7:0] input_addr_b = addr_b[7:0];
    wire [8:0] weight_addr_b = addr_b[8:0];
    wire [7:0] output_addr_b = addr_b[7:0];
    
    // ========== PORT A: WRITE/READ ==========
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            input_ready <= 1'b0;
            weight_ready <= 1'b0;
            output_valid <= 1'b0;
        end else begin
            // Write operations
            if (write_en_a) begin
                case (partition_a)
                    2'b00: begin  // Input SRAM (0x0000-0x00FF)
                        input_sram[input_addr_a] <= data_in_a;
                        input_ready <= 1'b1;
                    end
                    2'b01: begin  // Weight SRAM (0x0100-0x02FF)
                        weight_sram[weight_addr_a] <= data_in_a;
                        weight_ready <= 1'b1;
                    end
                    2'b10: begin  // Output SRAM (0x0300-0x03FF)
                        output_sram[output_addr_a] <= data_in_a;
                        output_valid <= 1'b1;
                    end
                endcase
            end
        end
    end
    
    // ========== PORT A: READ PATH ==========
    assign data_out_a = (read_en_a) ? 
        (partition_a == 2'b00) ? input_sram[input_addr_a] :
        (partition_a == 2'b01) ? weight_sram[weight_addr_a] :
        (partition_a == 2'b10) ? output_sram[output_addr_a] : 32'h0 : 32'h0;
    
    // ========== PORT B: READ ONLY (for PE Array) ==========
    assign data_out_b = (read_en_b) ?
        (partition_b == 2'b00) ? input_sram[input_addr_b] :
        (partition_b == 2'b01) ? weight_sram[weight_addr_b] :
        (partition_b == 2'b10) ? output_sram[output_addr_b] : 32'h0 : 32'h0;

endmodule
