class rx_payload_body_c extends uvm_object;

  function new(string name = "");
    super.new(name);
  endfunction

  rand bit [7:0] rx_payload[];

  constraint size_c {
    rx_payload.size() inside {[1:1023]};
  }

  `uvm_object_utils_begin(rx_payload_body_c)
    `uvm_field_array_int(rx_payload, UVM_DEFAULT)
  `uvm_object_utils_end

endclass
