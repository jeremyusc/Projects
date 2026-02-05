class rx_coverage_c extends uvm_subscriber #(rx_req_trans_c);
  `uvm_component_utils(rx_coverage_c)

  rx_req_trans_c m_req;
  integer trans_cnt = 0;
  integer remainder;

  covergroup covgrp;
    option.per_instance = 1;

    len_cp: coverpoint m_req.index {
      bins len_1 = {[1:127]};
      bins len_2 = {[128:255]};
      bins len_3 = {[256:383]};
      bins len_4 = {[384:511]};
      bins len_5 = {[512:639]};
      bins len_6 = {[640:767]};
      bins len_7 = {[768:895]};
      bins len_8 = {[896:1023]};
    }

    // remainder = m_req.rxd.size() % 4;

    vld_cp: coverpoint (m_req.index % 4) {
      bins full = {0};
      bins p1   = {1};
      bins p2   = {2};
      bins p3   = {3};
    }

    lenXvld: cross len_cp, vld_cp;
  endgroup

  function new(string name = "", uvm_component parent);
    super.new(name, parent);
    covgrp = new();
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // m_req = rx_req_trans_c::type_id::create("m_req");
  endfunction

  virtual function void write(rx_req_trans_c t);
    // assign received transaction to m_req
    if (t.rxdv) begin
      m_req = t;
      covgrp.sample();
    end

    if (t.last)
      `uvm_info(
        "COV_RX",
        $sformatf("Sample rxdv=%0d, rx_byte_cnt=%0d", t.rxdv, t.index),
        UVM_NONE
      )
  endfunction

endclass
