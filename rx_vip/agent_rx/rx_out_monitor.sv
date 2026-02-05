class rx_out_monitor_c extends uvm_monitor;
  `uvm_component_utils(rx_out_monitor_c) // Register this monitor with the UVM factory

  // Transaction object to store sampled signal values
  rx_rsp_trans_c     m_rsp;
  virtual rx_intf    vif;
  uvm_analysis_port #(rx_rsp_trans_c) m_ap;
  int rsp_byte_cnt = 0;

  // Constructor: name and parent passed to base class
  function new(string name = "", uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual rx_intf)::get(this, "", "rx_vif", vif)) begin
      `uvm_error("O_MON", "Failed to get rx_vif from config_db")
    end
    m_ap = new("m_ap", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    int index = 0;

    wait (vif.rst_n == 1);
    @(posedge vif.clk);

    forever begin
      @(posedge vif.clk);
      if (vif.valid_out && vif.conv_en) begin
        m_rsp = rx_rsp_trans_c::type_id::create("m_rsp");
        m_rsp.valid_out = 1;
        m_rsp.data_out  = vif.data_out;
        m_rsp.byte_cnt  = vif.byte_cnt;
        // m_rsp.byte_cnt = 4 * rsp_byte_cnt + 4;
        m_rsp.index     = index;
        // m_rsp.byte_cnt = vif.byte_cnt;
        m_rsp.last      = vif.last;

        `uvm_info(
          "O_MON",
          $sformatf(
            "DUT output[%0d]: valid_out=%0d, last=%0b, data_out=%0h, byte_cnt=%0d",
            m_rsp.index,
            m_rsp.valid_out,
            m_rsp.last,
            m_rsp.data_out,
            m_rsp.byte_cnt
          ),
          UVM_NONE
        )

        // Send the sampled transaction downstream
        m_ap.write(m_rsp);

        index++;
        rsp_byte_cnt++;
      end
    end
  endtask

endclass
