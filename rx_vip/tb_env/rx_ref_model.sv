class rx_ref_model_c extends uvm_component;
  `uvm_component_utils(rx_ref_model_c)

  logic [7:0] rxd_captured[4] = '{4{0}};
  int exp_byte_cnt = 0;

  // This class construction
  function new(string name = "", uvm_component parent);
    super.new(name, parent);
  endfunction

  // Construct components under this class
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
  endfunction

  task predict(
    input  rx_req_trans_c src_in,
    output rx_rsp_trans_c exp_out,
    inout  bit flag_4bytes
  );
    static int beat_index = 0;
    static int byte_pos   = 0;
    flag_4bytes = 0;

    rxd_captured[byte_pos] = src_in.rxd;
    byte_pos++;
    exp_byte_cnt++;

    exp_out = rx_rsp_trans_c::type_id::create("exp_out");

    if (byte_pos == 4) begin
      byte_pos    = 0;
      flag_4bytes = 1;
      exp_out.valid_out = 1;
      exp_out.data_out  = {
        rxd_captured[3],
        rxd_captured[2],
        rxd_captured[1],
        rxd_captured[0]
      };
      exp_out.last = src_in.last;

      if (src_in.last) begin
        exp_out.byte_cnt = exp_byte_cnt;
        exp_byte_cnt = 0;
      end
      else begin
        exp_out.byte_cnt = exp_byte_cnt;
      end
    end

    if (byte_pos != 0 && src_in.last) begin
      exp_out.valid_out = 1;
      for (int i = byte_pos; i < 4; i++) begin
        rxd_captured[i] = 8'h0;
      end

      exp_out.data_out = {
        rxd_captured[3],
        rxd_captured[2],
        rxd_captured[1],
        rxd_captured[0]
      };
      flag_4bytes = 1;
      byte_pos = 0;
      exp_out.last = src_in.last;
      exp_out.byte_cnt = exp_byte_cnt;
      exp_byte_cnt = 0;
    end
  endtask

endclass
