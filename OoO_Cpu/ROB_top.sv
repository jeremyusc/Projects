module Rename_ROB_top #(
    parameter DATA_WIDTH = 32,
    parameter RF_WIDTH   = 5,
    parameter PHY_WIDTH  = 7,
    parameter ROB_WIDTH  = 4
)(
    input                       clk, rst,

    // ---- 從 Decode 進來 ----
    input                       dec_valid,
    input  [RF_WIDTH-1:0]       dec_rs1, dec_rs2, dec_rd,
    input                       dec_use_rd,
    input                       dec_is_branch,
    input                       dec_is_store,

    // ---- 給 RS / EX (rename 結果) ----
    output [PHY_WIDTH-1:0]      dec_prs1, dec_prs2, // source PR
    output [PHY_WIDTH-1:0]      dec_prd,            // 新配的 PR
    output [ROB_WIDTH-1:0]      dec_rob_idx,        // 配的 ROB index
    output                      issue_fire,         // 這拍 rename+dispatch 成功

    // ---- Writeback (從 EX 回來) ----
    input                       wb_valid,
    input  [ROB_WIDTH-1:0]      wb_rob_idx,
    input                       wb_mispredict,

    // ---- Commit 觀測 / 給 store buffer ----
    output                      commit_valid,
    output                      commit_is_store,
    output                      flush               // = branch_mispredict
);

    // ---- 內部連線 ----
    wire [PHY_WIDTH-1:0] w_old_prs;
    wire                 w_alloc_ok;
    wire                 w_rob_full;
    wire [ROB_WIDTH-1:0] w_rob_idx;

    wire                 w_commit_valid;
    wire                 w_commit_use_rd;
    wire [RF_WIDTH-1:0]  w_commit_rd;
    wire [PHY_WIDTH-1:0] w_commit_prs;
    wire                 w_commit_old_prs_unused; // rename_unit 內部自己撈 RRAT,不靠這個
    wire                 w_flush;

    // =========================================================================
    // 全域 issue 條件:有合法指令 + free list 有得配 + ROB 沒滿 + 沒在 flush
    // =========================================================================
    wire issue_ready = dec_valid & w_alloc_ok & ~w_rob_full & ~w_flush;

    assign issue_fire  = issue_ready;
    assign dec_rob_idx = w_rob_idx;
    assign flush       = w_flush;

    // =========================================================================
    // Rename unit (RAT + Free list 合併版)
    // =========================================================================
    Rename #(
        .RF_WIDTH (RF_WIDTH),
        .PHY_WIDTH(PHY_WIDTH)
    ) u_rename (
        .clk              (clk),
        .rst              (rst),
        // rename in
        .dec_rs1          (dec_rs1),
        .dec_rs2          (dec_rs2),
        .dec_rd           (dec_rd),
        .dec_use_rd       (dec_use_rd),
        .issue_ready      (issue_ready),
        // rename out
        .dec_prs1         (dec_prs1),
        .dec_prs2         (dec_prs2),
        .dec_prd          (dec_prd),
        .dec_old_prs      (w_old_prs),
        .alloc_ok         (w_alloc_ok),
        // commit in (來自 ROB)
        .rob_commit_valid (w_commit_valid),
        .rob_commit_use_rd(w_commit_use_rd),
        .rob_commit_rd    (w_commit_rd),
        .rob_commit_prs   (w_commit_prs),
        // flush
        .branch_mispredict(w_flush)
    );

    // =========================================================================
    // ROB
    // =========================================================================
    ROB #(
        .RF_WIDTH (RF_WIDTH),
        .PHY_WIDTH(PHY_WIDTH),
        .ROB_WIDTH(ROB_WIDTH)
    ) u_rob (
        .clk                (clk),
        .rst                (rst),
        // dispatch:issue 成功才配 ROB entry
        .disp_valid         (issue_ready),
        .disp_use_rd        (dec_use_rd),
        .disp_arch_rd       (dec_rd),
        .disp_new_prs       (dec_prd),
        .disp_old_prs       (w_old_prs),
        .disp_is_branch     (dec_is_branch),
        .disp_is_store      (dec_is_store),
        .disp_rob_idx       (w_rob_idx),
        .rob_full           (w_rob_full),
        // writeback
        .wb_valid           (wb_valid),
        .wb_rob_idx         (wb_rob_idx),
        .wb_mispredict      (wb_mispredict),
        // commit out
        .rob_commit_valid   (w_commit_valid),
        .rob_commit_use_rd  (w_commit_use_rd),
        .rob_commit_rd      (w_commit_rd),
        .rob_commit_prs     (w_commit_prs),
        .rob_commit_old_prs (), // rename_unit 用 RRAT 撈,不接
        .rob_commit_is_store(commit_is_store),
        // flush
        .branch_mispredict  (w_flush)
    );

    assign commit_valid = w_commit_valid;

endmodule