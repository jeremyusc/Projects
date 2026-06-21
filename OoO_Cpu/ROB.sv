module ROB #(
    parameter RF_WIDTH  = 5,
    parameter PHY_WIDTH = 7,
    parameter ROB_WIDTH = 4               // 16 entry
)(
    input                       clk, rst,

    // =========================================================================
    // Dispatch (rename 完一條指令,配一個 ROB entry)
    // =========================================================================
    input                       disp_valid,     // 這拍有指令要進 ROB (= issue 成功)
    input                       disp_use_rd,
    input  [RF_WIDTH-1:0]       disp_arch_rd,
    input  [PHY_WIDTH-1:0]      disp_new_prs,
    input  [PHY_WIDTH-1:0]      disp_old_prs,
    input                       disp_is_branch,
    input                       disp_is_store,
    output [ROB_WIDTH-1:0]      disp_rob_idx,   // 配給這條指令的 ROB index (跟著進 RS)
    output                      rob_full,

    // =========================================================================
    // Writeback (EX 算完,標記 ready;branch 帶回 mispredict 結果)
    // =========================================================================
    input                       wb_valid,
    input  [ROB_WIDTH-1:0]      wb_rob_idx,
    input                       wb_mispredict,  // branch 算完:預測對不對

    // =========================================================================
    // Commit (送回 rename_unit)
    // =========================================================================
    output                      rob_commit_valid,
    output                      rob_commit_use_rd,
    output [RF_WIDTH-1:0]       rob_commit_rd,
    output [PHY_WIDTH-1:0]      rob_commit_prs,
    
    output                      rob_commit_is_store, // 給 store buffer:這拍 commit 的是 store

    // =========================================================================
    // Flush
    // =========================================================================
    output                      branch_mispredict
);

    localparam DEPTH = 1 << ROB_WIDTH;

    // ----- entry 欄位 (分開存,好讀好改) -----
    reg                  dirty      [0:DEPTH-1];
    reg                  ready      [0:DEPTH-1];
    reg                  use_rd     [0:DEPTH-1];
    reg [RF_WIDTH-1:0]   arch_rd    [0:DEPTH-1];
    reg [PHY_WIDTH-1:0]  new_prs    [0:DEPTH-1];
   
    reg                  is_branch  [0:DEPTH-1];
    reg                  is_store   [0:DEPTH-1];
    reg                  mispred    [0:DEPTH-1];

    reg [ROB_WIDTH:0]    head, tail;   // 多一個 bit 分辨滿/空 (wrap bit)

    wire [ROB_WIDTH-1:0] head_idx = head[ROB_WIDTH-1:0];
    wire [ROB_WIDTH-1:0] tail_idx = tail[ROB_WIDTH-1:0];

    wire rob_empty = (head == tail);
    assign rob_full = (head[ROB_WIDTH] != tail[ROB_WIDTH]) &&
                      (head_idx == tail_idx);

    assign disp_rob_idx = tail_idx;

    // ----- dispatch / commit 觸發 -----
    wire do_disp = disp_valid & ~rob_full;

    // commit:head entry 存在且已 ready
    wire head_ready = ~rob_empty & dirty[head_idx] & ready[head_idx];

    assign rob_commit_valid    = head_ready;
    assign rob_commit_use_rd   = use_rd[head_idx];
    assign rob_commit_rd       = arch_rd[head_idx];
    assign rob_commit_prs      = new_prs[head_idx];
    
    assign rob_commit_is_store = is_store[head_idx];

    // commit 的是 branch 且預測錯 → flush
    assign branch_mispredict = head_ready & is_branch[head_idx] & mispred[head_idx];

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            head <= 0;
            tail <= 0;
            for (i = 0; i < DEPTH; i = i + 1) dirty[i] <= 1'b0;
        end else if (branch_mispredict) begin
            //flush rob
            head <= 0;
            tail <= 0;
            for (i = 0; i < DEPTH; i = i + 1) dirty[i] <= 1'b0;
        end else begin
            // ---- dispatch:寫 tail entry ----
            if (do_disp) begin
                dirty     [tail_idx] <= 1'b1;
                ready    [tail_idx] <= 1'b0;
                use_rd   [tail_idx] <= disp_use_rd;
                arch_rd  [tail_idx] <= disp_arch_rd;
                new_prs  [tail_idx] <= disp_new_prs;
                old_prs  [tail_idx] <= disp_old_prs;
                is_branch[tail_idx] <= disp_is_branch;
                is_store [tail_idx] <= disp_is_store;
                mispred  [tail_idx] <= 1'b0;
                tail <= tail + 1;
            end

            // ---- writeback:標記 ready + branch 結果 ----
            if (wb_valid) begin
                ready  [wb_rob_idx] <= 1'b1;
                mispred[wb_rob_idx] <= wb_mispredict;
            end

            // ---- commit:head entry ready 就退休 ----
            if (rob_commit_valid) begin
                dirty[head_idx] <= 1'b0;
                head <= head + 1;
            end
        end
    end

endmodule