class rx_in_monitor_c extends uvm_monitor;
  `uvm_component_utils(rx_in_monitor_c) // Register this monitor with the UVM factory

  rx_req_trans_c     m_req;
  rx_req_trans_c     m_pre;
  virtual rx_intf    vif;
  uvm_analysis_port #(rx_req_trans_c) m_ap;

  // Constructor: name and parent passed to base class
  function new(string name = "", uvm_component parent);
    super.new(name, parent);
  endfunction

  // Build phase: create transaction object
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual rx_intf)::get(this, "", "rx_vif", vif)) begin
      `uvm_error("IMON", "Failed to get rx_vif from config_db")
    end
    // Create the analysis port for this monitor
    m_ap = new("m_ap", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    int index = 0;
    bit rx_last = 0;
    bit rxing   = 0;
    bit [7:0] current_rxd, delay_rxd;

    wait (vif.rst_n == 1);

    forever begin
      @(posedge vif.clk);

      if (vif.rxdv && vif.conv_en) begin
        current_rxd = vif.rxd;
        if (rxing) begin
          m_req = rx_req_trans_c::type_id::create("m_req");
          m_req.conv_en = 1;
          m_req.rxdv    = 1;
          m_req.rxd     = delay_rxd;
          m_req.last    = 0;
          m_req.index   = index;

          `uvm_info(
            "IMON_RX",
            $sformatf("In -> %0s", m_req.convert2string()),
            UVM_MEDIUM
          )

          m_ap.write(m_req);
          index++;
        end
        rxing = 1;
        delay_rxd = current_rxd;
      end

      else if (vif.rxdv && rxing && vif.conv_en) begin
        m_req = rx_req_trans_c::type_id::create("m_req");
        rxing = 0;
        m_req.conv_en = 1;
        m_req.rxdv    = 1;
        m_req.rxd     = delay_rxd;
        m_req.index   = index;
        rx_last = 1;
        m_req.last = rx_last;

        m_ap.write(m_req);
        `uvm_info(
          "IMON_RX",
          $sformatf("Write %0s", m_req.convert2string()),
          UVM_MEDIUM
        )
      end

      else if (rx_last) begin
        rx_last = 0;
        index   = 0;
      end

      else begin
        index = 0;
      end

    end
  endtask

endclass
