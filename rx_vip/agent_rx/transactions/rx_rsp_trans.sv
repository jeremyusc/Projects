class rx_rsp_trans_c extends packet_base_trans_c;

  // Constructor: pass the name to the base class
  function new(string name = "");
    super.new(name);
  endfunction

  bit        valid_out;
  bit [31:0] data_out;
  bit [9:0]  byte_cnt;
  bit        last;

  function string convert2string();
    return $sformatf(
      "data_out[%0d]=%0h, valid_out=%0b, byte_cnt=%0d, last=%0b",
      index, data_out, valid_out, byte_cnt, last
    );
  endfunction

  // Register fields for automatic record/print/compare
  `uvm_object_utils_begin(rx_rsp_trans_c)
    `uvm_field_int(valid_out, UVM_DEFAULT)
    `uvm_field_int(data_out,  UVM_DEFAULT)
    `uvm_field_int(last,      UVM_DEFAULT)
    `uvm_field_int(byte_cnt,  UVM_DEFAULT)
  `uvm_object_utils_end

endclass
