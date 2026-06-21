module Rename_unit #(
    parameter ADDR       = 10,
    parameter DATA_WIDTH = 32,
    parameter RF_WIDTH   = 5,    // 架構暫存器位元數 (5 -> 32 ARF)
    parameter PHY_WIDTH  = 7     // 實體暫存器位元數 (7 -> 128 PRF)
)(
    input                       clk, rst,

    // =========================================================================
    // 1. Frontend Rename (來自 Decode)
    // =========================================================================
    input  [RF_WIDTH-1:0]       dec_rs1, dec_rs2,
    input  [RF_WIDTH-1:0]       dec_rd,
    input                       dec_use_rd,        // 這條指令有沒有寫 rd
    input                       issue_ready,       // 這拍 rename 成功前進 (上游已 AND: ROB 沒滿 / 沒 flush)

    output [PHY_WIDTH-1:0]      dec_prs1, dec_prs2, // source 映射 -> 給 RS
    output [PHY_WIDTH-1:0]      dec_prd,            // 新配給 rd 的 PR -> 給 RS / ROB
    output [PHY_WIDTH-1:0]      dec_old_prs,        // rd 覆蓋前的舊映射 -> 存進 ROB
    output                      alloc_ok,           // free list 有得配 (空了要 stall 上游)

    // =========================================================================
    // 2. Backend Commit (來自 ROB)
    // =========================================================================
    input                       rob_commit_valid,
    input                       rob_commit_use_rd,  // ROB 保管的、這條指令當初的 dec_use_rd
    input  [RF_WIDTH-1:0]       rob_commit_rd,
    input  [PHY_WIDTH-1:0]      rob_commit_prs,     // 這條指令的新結果 PR -> 寫進 RRAT

    // =========================================================================
    // 3. Branch Misprediction Recovery
    // =========================================================================
    input                       branch_mispredict
);

    localparam RF_NUM = 1 << RF_WIDTH;  // 32
    localparam DEPTH  = 1 << PHY_WIDTH; // 128

    // ----- RAT -----
    reg [PHY_WIDTH-1:0] frat [0:RF_NUM-1]; // 投機映射,供 rename 查
    reg [PHY_WIDTH-1:0] rrat [0:RF_NUM-1]; // 確定映射,供 flush 還原 + 安全回收

    // ----- Free list (circular FIFO) -----
    reg [PHY_WIDTH-1:0] fifo [0:DEPTH-1];
    reg [PHY_WIDTH:0]   w_ptr;        // 回收寫指標
    reg [PHY_WIDTH:0]   r_ptr;        // speculative 讀指標 (含錯路 pop)
    reg [PHY_WIDTH:0]   r_ptr_commit; // committed 讀指標 (配 PR 的指令 commit 才 ++)

    // =========================================================================
    // 統一條件 — rename 端與 commit 端各一份,寫 r0 視同不寫 (r0 恆為 0 不 rename)
    // =========================================================================
    wire rename_alloc = dec_use_rd       & (dec_rd != 0);
    wire commit_write = rob_commit_use_rd & (rob_commit_rd != 0);

    // =========================================================================
    // Free list 狀態
    // =========================================================================
    wire fl_full  = (w_ptr[PHY_WIDTH] != r_ptr[PHY_WIDTH]) &&
                    (w_ptr[PHY_WIDTH-1:0] == r_ptr[PHY_WIDTH-1:0]);
    wire fl_empty = (w_ptr == r_ptr);

    wire [PHY_WIDTH-1:0] free_phy_reg = fifo[r_ptr[PHY_WIDTH-1:0]];

    // pop: 真的要配 PR、free list 非空、這拍前進
    // push: 真的踩掉舊映射 (commit 且寫 rd 且非 r0)
    wire r_en = rename_alloc & !fl_empty & issue_ready;
    wire w_en = commit_write & rob_commit_valid & !fl_full;

    assign alloc_ok = !fl_empty;   // free list 空 -> 上游要 stall

    // =========================================================================
    // RAT 組合讀 (rename)
    // =========================================================================
    assign dec_prs1   = frat[dec_rs1];   // source 讀更新前的映射
    assign dec_prs2   = frat[dec_rs2];
    assign dec_old_prs = frat[dec_rd];   // rd 覆蓋前的舊映射 -> ROB
    assign dec_prd    = free_phy_reg;    // 新配的 PR

    // =========================================================================
    // commit 撈 RRAT 舊值 (覆蓋前) -> 內部直接 push 回 free list
    // 用 RRAT 為準:mispredict 還原後 ROB 的 old_prs 可能指向有效 PR
    // =========================================================================
    wire [PHY_WIDTH-1:0] commit_old_prs = rrat[rob_commit_rd];

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            // RAT 初始:arch i -> phys i
            for (i = 0; i < RF_NUM; i = i + 1) begin
                frat[i] <= i[PHY_WIDTH-1:0];
                rrat[i] <= i[PHY_WIDTH-1:0];
            end
            // Free list 初始:PR32 ~ PR127 (96 個 free)
            r_ptr        <= 0;
            r_ptr_commit <= 0;
            w_ptr        <= DEPTH - RF_NUM;
            for (i = 0; i < DEPTH - RF_NUM; i = i + 1)
                fifo[i] <= i[PHY_WIDTH-1:0] + RF_NUM;
        end else begin
            // =================================================================
            // FRAT 更新 / 還原
            // =================================================================
            if (branch_mispredict) begin
                for (i = 0; i < RF_NUM; i = i + 1)
                    frat[i] <= rrat[i];           // 一次抹掉錯路污染
            end else if (issue_ready && rename_alloc && !fl_empty) begin
                frat[dec_rd] <= free_phy_reg;     // rd 指向新 PR
            end

            // =================================================================
            // RRAT 更新 (真正 commit 且寫 rd 才動)
            // =================================================================
            if (rob_commit_valid && commit_write)
                rrat[rob_commit_rd] <= rob_commit_prs;

            // =================================================================
            // Free list — push (回收) / pop / flush rollback
            // =================================================================
            if (w_en) begin
                fifo[w_ptr[PHY_WIDTH-1:0]] <= commit_old_prs; // 還 RRAT 舊值
                w_ptr        <= w_ptr + 1;
                r_ptr_commit <= r_ptr_commit + 1;             // committed 邊界前進
            end

            if (branch_mispredict)
                r_ptr <= r_ptr_commit;            // 錯路 pop 一次退回
            else if (r_en)
                r_ptr <= r_ptr + 1;
        end
    end

endmodule