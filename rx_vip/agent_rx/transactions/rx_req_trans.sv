class rx_req_trans_c extends packet_base_trans_c;

  function new(string name = "");
    super.new(name);
  endfunction

  rand bit [7:0] rxd;
  bit rxdv;
  bit conv_en;

  typedef enum { T_DATA, T_TRANS_END } cmd_t;
  rand cmd_t cmd;
  rand int repeat_cycles;

  function string convert2string();
    return $sformatf(
      "rxd[%0d]=%0h, conv_en=%0d, rxdv=%0d",
      index, rxd, conv_en, rxdv
    );
  endfunction

  // Register fields for automatic record/print/compare
  `uvm_object_utils_begin(rx_req_trans_c)
    `uvm_field_int(conv_en, UVM_DEFAULT)
    `uvm_field_int(rxdv,    UVM_DEFAULT)  // Calculated index
    `uvm_field_int(rxd,     UVM_DEFAULT)
  `uvm_object_utils_end

endclass
