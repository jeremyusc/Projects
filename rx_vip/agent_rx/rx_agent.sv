class rx_agent_c extends uvm_agent;
  uvm_component_utils(rx_agent_c)

  uvm_sequencer #(rx_req_trans_c) m_sqr;
  rx_in_monitor_c  m_imon;
  rx_out_monitor_c m_omon;
  rx_driver_c      m_drv;

  function new(string name = "", uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    m_drv  = rx_driver_c::type_id::create("m_drv",  this);
    m_sqr  = uvm_sequencer #(rx_req_trans_c)::type_id::create("m_sqr",  this);
    m_imon = rx_in_monitor_c::type_id::create("m_imon", this);
    m_omon = rx_out_monitor_c::type_id::create("m_omon", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    m_drv.seq_item_port.connect(m_sqr.seq_item_export);
  endfunction

endclass
