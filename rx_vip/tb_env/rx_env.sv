class rx_env_c extends uvm_env;
  `uvm_component_utils(rx_env_c)

  rx_agent_c      m_rx_agt;
  rx_coverage_c   m_rx_cov;
  rx_scoreboard_c m_rx_sb;
  virtual rx_intf vif;

  function new(string name = "", uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    m_rx_agt = rx_agent_c::type_id::create("m_rx_agt", this);
    m_rx_cov = rx_coverage_c::type_id::create("m_rx_cov", this);
    m_rx_sb  = rx_scoreboard_c::type_id::create("m_rx_sb",  this);

    if (!uvm_config_db #(virtual rx_intf)::get(this, "", "rx_vif", vif))
      `uvm_error("RX_ENV_C", "FAILED rx_env_c")
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // in_monitor -> scoreboard + coverage
    m_rx_agt.m_imon.m_ap.connect(m_rx_sb.input_fifo.analysis_export);
    m_rx_agt.m_imon.m_ap.connect(m_rx_cov.analysis_export);

    // out_monitor -> scoreboard
    m_rx_agt.m_omon.m_ap.connect(m_rx_sb.o_mon_fifo.analysis_export);
  endfunction

endclass
