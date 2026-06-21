module branch_predictor #(
    parameter ADDR      = 10,
    parameter BTB_ENTRY = 16,
    parameter BPB_ENTRY = 16
)(
    input                 clk, rst,

    // ---- fetch / predict ----
    input      [ADDR-1:0] current_pc,
    output                predict_taken,    // 是否重導向 fetch
    output     [ADDR-1:0] predict_target,

    // ---- update（分支 resolve 後回寫）----
    input                 update_en,        // 這個 cycle 有分支被解出
    input      [ADDR-1:0] update_pc,
    input                 actual_taken,     // 實際方向
    input      [ADDR-1:0] actual_target     // 實際目標(taken 時用)
);

    wire [ADDR-1:0] btb_target;
    wire            btb_hit;
    wire            bpb_taken;

    // 只有方向預測 taken 且 BTB 有 target 才真的跳
    assign predict_taken  = bpb_taken & btb_hit;
    assign predict_target = btb_target;

    BTB #(
        .ADDR(ADDR),
        .BTB_ENTRY(BTB_ENTRY)
    ) u_btb (
        .clk(clk), .rst(rst),
        .current_pc(current_pc),
        
        // 只在「實際 taken」時才把 target 寫進 BTB
        .update_en(update_en & actual_taken),
        .update_pc(update_pc),
        .update_target(actual_target),
        ///output
        .target_pc(btb_target),
        .btb_hit(btb_hit)
    );

    BPB #(
        .ADDR(ADDR),
        .BPB_ENTRY(BPB_ENTRY)
    ) u_bpb (
        .clk(clk), .rst(rst),
        .current_pc(current_pc),
        // 方向預測器每次 resolve 都要更新(taken/not 都學)
        .update_en(update_en),
        .update_pc(update_pc),
        .actual_taken(actual_taken),
        ///output
        .branch_taken(bpb_taken)
    );

endmodule