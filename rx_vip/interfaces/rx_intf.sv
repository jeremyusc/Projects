interface rx_intf (input bit clk, rst_n);

  // ------------------------------------------------------------------
  // Control & data signals between TB and DUT
  // ------------------------------------------------------------------
  logic        conv_en;   // Conversion enable (start 8->32 packing)
  logic        rxdv;      // Receive-data valid indicator
  logic [7:0]  rxd;       // Serial 8-bit data input

  logic        valid_out; // One-cycle pulse when data_out is updated
  logic        last;      // One-cycle pulse marking final 32-bit word
  logic [9:0]  byte_cnt;  // Receive Byte Count
  logic [31:0] data_out;  // Parallel 32-bit output

  // ------------------------------------------------------------------
  // Modports
  // ------------------------------------------------------------------
  // DUT drives valid_out/last/byte_cnt/data_out; sees conv_en/rxdv/rxd as inputs.
  // (rst_n is wired directly to the DUT in top; not required in dut modport.)
  modport dut (
    input  conv_en, rxdv, rxd,
    output valid_out, last, byte_cnt, data_out
  );

  // Testbench drives conv_en/rxdv/rxd; monitors DUT outputs and reset.
  // Expose rst_n as input so driver/monitor can synchronize to reset release.
  modport tb (
    input  rst_n, valid_out, last, byte_cnt, data_out,
    output conv_en, rxdv, rxd
  );

endinterface : rx_intf
