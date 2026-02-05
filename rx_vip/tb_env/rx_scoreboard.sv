class rx_scoreboard_c extends uvm_scoreboard;
  `uvm_component_utils(rx_scoreboard_c)

  rx_ref_model_c m_refmod;
  uvm_tlm_analysis_fifo #(rx_req_trans_c) input_fifo;
  uvm_tlm_analysis_fifo #(rx_rsp_trans_c) o_mon_fifo;
  uvm_tlm_fifo #(rx_rsp_trans_c) expect_fifo;

  int total_trans;
  int total_match;
  int total_mismatch;
  int process_input_cnt;
  int process_output_cnt;

  function new(string name = "", uvm_component parent);
    super.new(name, parent);
    total_trans    = 0;
    total_match    = 0;
    total_mismatch = 0;
  endfunction

  virtual function string convert2string();
    real   match_rate;
    string s;

    match_rate = total_trans ? (total_match * 100.0 / total_trans) : 0;

    s = super.convert2string();
    s = {s, "\n"};
    s = {s, "============================================================\n"};
    s = {s, $sformatf("%0s Scoreboard Report\n", get_full_name())};
    s = {s, "============================================================\n"};
    s = {s, "Transaction Summary\n"};
    s = {s, $sformatf("Total      : %0d\n", total_trans)};
    s = {s, $sformatf("Match      : %0d (%0.2f%%)\n", total_match, match_rate)};
    s = {s, $sformatf("MisMatch   : %0d\n", total_mismatch)};
    s = {s, "------------------------------------------------------------\n"};

    return s;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    o_mon_fifo   = new("o_mon_fifo", this);
    m_refmod     = rx_ref_model_c::type_id::create("m_refmod", this);
    input_fifo   = new("input_fifo", this);
    expect_fifo  = new("expect_fifo", this, 16);
  endfunction
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    o_mon_fifo   = new("o_mon_fifo", this);
    m_refmod     = rx_ref_model_c::type_id::create("m_refmod", this);
    input_fifo   = new("input_fifo", this);
    expect_fifo  = new("expect_fifo", this, 16);
  endfunction

  bit flag_4bytes;

  task process_input();
    rx_req_trans_c m_req;
    rx_rsp_trans_c m_exp;

    forever begin
      input_fifo.get(m_req);
      `uvm_info(
        "SCR",
        $sformatf(
          "RCV from I_MON[%0d]: conv_en=%0b, rxdv=%0d, rxd=%0d, last=%0b",
          process_input_cnt,
          m_req.conv_en,
          m_req.rxdv,
          m_req.rxd,
          m_req.last
        ),
        UVM_LOW
      )

      m_refmod.predict(m_req, m_exp, flag_4bytes);
      if (flag_4bytes)
        expect_fifo.put(m_exp);

      process_input_cnt++;
    end
  endtask

  task process_out();
    rx_rsp_trans_c m_rsp;
    rx_rsp_trans_c m_exp;

    forever begin
      o_mon_fifo.get(m_rsp);
      expect_fifo.get(m_exp);

      `uvm_info(
        "SCR",
        $sformatf(
          "RCV from O_MON[%0d] valid_out=%0d, last=%0b, data_out=%02H, byte_cnt=%0d",
          process_output_cnt,
          m_rsp.valid_out,
          m_rsp.last,
          m_rsp.data_out,
          m_rsp.byte_cnt
        ),
        UVM_LOW
      )

      if ((m_rsp.valid_out == m_exp.valid_out) &&
          (m_rsp.last      == m_exp.last) &&
          (m_rsp.data_out  == m_exp.data_out) &&
          (m_rsp.byte_cnt  == m_exp.byte_cnt)) begin

        total_match++;
        `uvm_info(
          "SCR",
          $sformatf(
            "PASS: valid_out=%0d, last=%0b, data_out=%02H, byte_cnt=%0d",
            m_rsp.valid_out,
            m_rsp.last,
            m_rsp.data_out,
            m_exp.byte_cnt
          ),
          UVM_LOW
        )
      end
      else begin
        total_mismatch++;
        `uvm_error(
          "SCR",
          $sformatf(
            "!!!!! rspdata=%02H, exp=%02H !!!!! rsp v=%0d!! exp v=%0d!!!! last %0b %0b!!!!! rsp=%0d, exp=%0d",
            m_rsp.data_out,
            m_exp.data_out,
            m_rsp.valid_out,
            m_exp.valid_out,
            m_rsp.last,
            m_exp.last,
            m_rsp.byte_cnt,
            m_exp.byte_cnt
          )
        )
      end

      total_trans++;
      process_output_cnt++;
    end
  endtask

  task run_phase(uvm_phase phase);
    fork
      process_input();
      process_out();
      // #400000 $finish();
    join
  endtask

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (process_input_cnt != process_output_cnt) begin
      `uvm_error(
        "SCR",
        $sformatf(
          "Index Mismatch input[%0d] output[%0d]",
          process_input_cnt,
          process_output_cnt
        )
      )
    end
  endfunction

endclass
