class rx_sequence_c extends uvm_sequence #(rx_req_trans_c);
  `uvm_object_utils(rx_sequence_c)

  rx_payload_body_c m_payload;
  rx_req_trans_c    m_req;
  int byte_index = 0;
  int last_pack  = 0;

  function new(string name = "");
    super.new(name);
  endfunction

  virtual task body();
    m_payload = rx_payload_body_c::type_id::create("m_payload");

    if (!m_payload.randomize())
      `uvm_error("SEQ", "FAILED to randomize payload")
    else
      `uvm_info(
        "SEQ",
        $sformatf(
          "Total %0d packs data are generated",
          m_payload.rx_payload.size()
        ),
        UVM_NONE
      )

    foreach (m_payload.rx_payload[i]) begin
      m_req = rx_req_trans_c::type_id::create("m_req");
      m_req.cmd = rx_req_trans_c::T_DATA;
      start_item(m_req);

      m_req.conv_en = 1;
      m_req.rxdv    = 1;
      m_req.rxd     = m_payload.rx_payload[i];
      m_req.index   = byte_index;

      `uvm_info(
        "SEQ",
        $sformatf(
          "#[%0d] conv_en=%0d rxdv=%0d rxd=%0p",
          byte_index,
          m_req.conv_en,
          m_req.rxdv,
          m_req.rxd
        ),
        UVM_NONE
      )

      byte_index++;
      if (m_payload.rx_payload[i] == m_payload.rx_payload.size())
        last_pack = 1;

      finish_item(m_req);
    end

    if (last_pack) begin
      start_item(m_req);
      m_req.cmd           = rx_req_trans_c::T_TRANS_END;
      m_req.repeat_cycles = 2;
      m_req.rxdv          = 0;
      m_req.rxd           = 0;
      finish_item(m_req);
    end
  endtask

endclass
