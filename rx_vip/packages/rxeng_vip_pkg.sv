package rx_vip_pkg;

  `include "uvm_macros.svh"
  import uvm_pkg::*;

  `include "packages/packet_base_trans.sv"

  // ---------------------------------------------------------------
  // Transactions and Sequence (must come first)
  // ---------------------------------------------------------------
  `include "agent_rx/transactions/rx_req_trans.sv"
  `include "agent_rx/transactions/rx_rsp_trans.sv"
  `include "agent_rx/transactions/rx_payload_body.sv"
  `include "agent_rx/sequences/rx_sequence.sv"

  // ---------------------------------------------------------------
  // agent rx
  // ---------------------------------------------------------------
  `include "agent_rx/rx_driver.sv"
  `include "agent_rx/rx_in_monitor.sv"
  `include "agent_rx/rx_out_monitor.sv"
  `include "agent_rx/rx_agent.sv"

  // ---------------------------------------------------------------
  // Scoreboard and Environment
  // ---------------------------------------------------------------
  `include "tb_env/rx_coverage.sv"
  `include "tb_env/rx_ref_model.sv"
  `include "tb_env/rx_scoreboard.sv"
  `include "tb_env/rx_env.sv"

endpackage
