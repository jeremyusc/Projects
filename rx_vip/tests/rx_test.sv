`include "uvm_macros.svh"
import uvm_pkg::*;
import rx_vip_pkg::*;

class rx_test extends uvm_test;
  `uvm_component_utils(rx_test)

  rx_env_c      m_rx_env;
  rx_sequence_c m_rx_seq;

  int  covered_bins, total_bins;
  real coverage_percent = 0.00;

  function new(string name = "", uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    m_rx_env = rx_env_c::type_id::create("m_rx_env", this);
  endfunction

  virtual function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_default_printer.knobs.depth = 3;
    uvm_top.print_topology();
  endfunction

  virtual task main_phase(uvm_phase phase);
    phase.raise_objection(this);

    wait (m_rx_env.vif.rst_n == 1);

    for (int i = 0; i < 50; i++) begin
      m_rx_seq = rx_sequence_c::type_id::create("sequence");
      m_rx_seq.start(m_rx_env.m_rx_agt.m_sqr);

      `uvm_info(
        "MAIN",
        $sformatf(
          "Coverage = %0.2f %%", 
          m_rx_env.m_rx_cov.covgrp.get_coverage()
        ),
        UVM_NONE
      )

      @(posedge m_rx_env.vif.clk);
    end

    phase.drop_objection(this);
  endtask

  virtual task shutdown_phase(uvm_phase phase);
    coverage_percent =
      m_rx_env.m_rx_cov.covgrp.get_inst_coverage(
        covered_bins, total_bins
      );

    `uvm_info(
      "TEST",
      $sformatf(
        "INST Coverage = %0.2f %% --> Covered = %0d, Total = %0d",
        coverage_percent, covered_bins, total_bins
      ),
      UVM_NONE
    )

    `uvm_info(
      "TEST",
      $sformatf(
        "LEN_CP Coverage Coverage = %0.2f %%",
        m_rx_env.m_rx_cov.covgrp.len_cp.get_coverage()
      ),
      UVM_NONE
    )

    `uvm_info(
      "TEST",
      $sformatf(
        "LVD_CP Coverage Coverage = %0.2f %%",
        m_rx_env.m_rx_cov.covgrp.vld_cp.get_coverage()
      ),
      UVM_NONE
    )

    `uvm_info(
      "TEST",
      $sformatf(
        "LENXLD Coverage_Coverage = %0.2f %%",
        m_rx_env.m_rx_cov.covgrp.lenXvld.get_coverage()
      ),
      UVM_NONE
    )
  endtask

  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(
      "TEST",
      m_rx_env.m_rx_sb.convert2string(),
      UVM_NONE
    )
  endfunction

endclass
