module rx_eng (
    input        clk,        // Clock input
    input        rst_n,        // Asynchronous reset (active low), synchronous release
    input        conv_en,     // Conversion enable: hold high during valid bytes
    input        rxdv,        // RX data valid indicator
    input  [7:0] rxd,         // Incoming serial byte
    output reg   valid_out,   // Asserted when a 32-bit word is ready
    output reg   last,        // Asserted high on the cycle of the final word
    output reg [9:0]  byte_cnt, // Receive Byte Count
    output reg [31:0] data_out  // Assembled 32-bit parallel output
);
