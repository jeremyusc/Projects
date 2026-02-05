class rx_driver_c extends uvm_driver #(rx_req_trans_c);
  `uvm_component_utils(rx_driver_c)

  rx_req_trans_c m_req;
  virtual rx_intf vif;

  function new(string name = "", uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual rx_intf)::get(this, "", "rx_vif", vif))
      `uvm_error("DRV", "FAILED TO ACCESS DUT")
  endfunction

  virtual task run_phase(uvm_phase phase);
    int index = 0;
    wait (vif.rst_n == 1);
    forever begin
      seq_item_port.get_next_item(m_req);
      case (m_req.cmd)
        rx_req_trans_c::T_DATA: begin
          vif.conv_en <= m_req.conv_en;
          vif.rxdv    <= m_req.rxdv;
          vif.rxd     <= m_req.rxd;
          @(posedge vif.clk);
        end

        rx_req_trans_c::T_TRANS_END: begin
          vif.conv_en <= m_req.conv_en;
          vif.rxdv    <= m_req.rxdv;
          repeat (m_req.repeat_cycles) @(posedge vif.clk);
        end
      endcase

      m_req.index = index;
      seq_item_port.item_done();

      `uvm_info(
        "DRV",
        $sformatf(
          "DRIVE to DUT[%0d] conv_en=%0d, rxdv=%0d, rxd=%0d",
          m_req.index, m_req.conv_en, m_req.rxdv, m_req.rxd
        ),
        UVM_NONE
      )
      `uvm_info(
        "DRV",
        $sformatf(
          "Convert2string DRV to DUT %0s",
          m_req.convert2string()
        ),
        UVM_NONE
      )
      index++;
    end
  endtask

endclass
