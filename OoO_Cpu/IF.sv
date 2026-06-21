module Inst_queue #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 4,
    parameter FIFO_DEPTH = 8
)(
    input  clk, rst,
    // write side (from IF)
    input  [DATA_WIDTH-1:0] din,
    input  w_en,
    output full,
    // read side (to dispatch)
    input  r_en,
    output [DATA_WIDTH-1:0] dout,
    output empty
);

    reg [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];
    reg [ADDR_WIDTH-1:0] w_ptr;
    reg [ADDR_WIDTH-1:0] r_ptr;

    assign full  = (w_ptr[ADDR_WIDTH-1] != r_ptr[ADDR_WIDTH-1]) &&
                   (w_ptr[ADDR_WIDTH-2:0] == r_ptr[ADDR_WIDTH-2:0]);
    assign empty = (w_ptr == r_ptr);
    assign dout  = mem[r_ptr[ADDR_WIDTH-2:0]];

    always @(posedge clk) begin
        if (rst) begin
            w_ptr <= 0;
            r_ptr <= 0;
        end else begin
            case ({!full && w_en, !empty && r_en})
                2'b01: r_ptr <= r_ptr + 1;
                2'b10: begin
                    mem[w_ptr[ADDR_WIDTH-2:0]] <= din;
                    w_ptr <= w_ptr + 1;
                end
                2'b11: begin
                    mem[w_ptr[ADDR_WIDTH-2:0]] <= din;
                    r_ptr <= r_ptr + 1;
                    w_ptr <= w_ptr + 1;
                end
                default: ;
            endcase
        end
    end

endmodule


module IF #(
    parameter DATA_WIDTH = 32,
    parameter ADDR       = 10,
    parameter IQ_DEPTH   = 8,
    parameter IQ_AW      = 4        // ceil(log2(IQ_DEPTH)) + 1
)(
    input  clk, rst,

    // branch prediction
    input  [ADDR-1:0] predict_target,
    input             predict_taken,

    // pipeline stall (issue queue full)
    input             stall,

    // redirect / mispredict flush
    input             redirect,
    input  [ADDR-1:0] redirect_pc,

    // issue queue read port (to dispatch stage)
    input             iq_r_en,
    output [DATA_WIDTH-1:0] iq_dout,
    output            iq_empty,

    // current PC (for decode / debug)
    output [ADDR-1:0] current_pc
);

    // ----------------------------------------------------------------
    // Instruction memory  (256 x DATA_WIDTH, word-addressed)
    // ----------------------------------------------------------------
    reg [DATA_WIDTH-1:0] inst_mem [0:255];

    wire [ADDR-3:0] addr = pc[ADDR-1:2];

    // ----------------------------------------------------------------
    // PC register
    // ----------------------------------------------------------------
    reg [ADDR-1:0] pc;
    assign current_pc = pc;

    // ----------------------------------------------------------------
    // Issue queue instantiation
    // ----------------------------------------------------------------
    wire iq_full;
    wire [DATA_WIDTH-1:0] fetched_inst = inst_mem[addr];

    // Write into the queue whenever we fetch (not stalled, not redirecting)
    wire iq_w_en = !stall && !redirect;

    Inst_queue #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (IQ_AW),
        .FIFO_DEPTH (IQ_DEPTH)
    ) u_iq (
        .clk   (clk),
        .rst   (rst || redirect),   // flush queue on redirect
        .din   (fetched_inst),
        .w_en  (iq_w_en),
        .full  (iq_full),
        .r_en  (iq_r_en),
        .dout  (iq_dout),
        .empty (iq_empty)
    );

    // ----------------------------------------------------------------
    // PC update logic
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (rst)
            pc <= 0;
        else if (redirect)
            pc <= redirect_pc;
        else if (stall || iq_full)   // back-pressure: stop fetching
            pc <= pc;
        else if (predict_taken)
            pc <= predict_target;
        else
            pc <= pc + 4;
    end

endmodule