module uvmtb_rx;
  bit clk;
  bit rst_n;

  initial clk = 0;
  always #10 clk = ~clk;

  initial begin
    rst_n = 0;
    $display("time %0t rst_n %0d(before)", $time, rst_n);
    #20 rst_n = 1;
    $display("time %0t rst_n %0d(after)", $time, rst_n);
  end

  rx_intf vif (.clk(clk), .rst_n(rst_n));

  rx_eng dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .conv_en   (vif.conv_en),
    .rxdv      (vif.rxdv),
    .rxd       (vif.rxd),
    .valid_out (vif.valid_out),
    .last      (vif.last),
    .data_out  (vif.data_out),
    .byte_cnt  (vif.byte_cnt)
  );

  initial begin
    uvm_config_db #(virtual rx_intf)::set(null, "*", "rx_vif", vif);
    run_test();
  end

endmodule
