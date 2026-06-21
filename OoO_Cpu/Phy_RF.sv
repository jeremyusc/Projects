module Phy_RF #(
    parameter DATA_WIDTH = 32,
    parameter PHY_WIDTH  = 7,            // 128 PR
    parameter RF_WIDTH   = 5             // 初始 PR0~31 對應 arch reg
)(
    input                       clk, rst,

    // ---- 讀 port (RS 發射時讀 operand) ----
    input  [PHY_WIDTH-1:0]      rd_prs1,
    input  [PHY_WIDTH-1:0]      rd_prs2,
    output [DATA_WIDTH-1:0]     rd_val1,
    output [DATA_WIDTH-1:0]     rd_val2,

    // ---- ready 查詢 (RS dispatch / wakeup 用) ----
    input  [PHY_WIDTH-1:0]      q_prs1,        // 查這個 PR 值好了沒
    input  [PHY_WIDTH-1:0]      q_prs2,
    output                      q_rdy1,
    output                      q_rdy2,

    // ---- 寫 port (writeback) ----
    input                       wb_valid,
    input  [PHY_WIDTH-1:0]      wb_prs,
    input  [DATA_WIDTH-1:0]     wb_data,

    // ---- 新配 PR:rename 配出去時標記成「未就緒」 ----
    input                       alloc_valid,
    input  [PHY_WIDTH-1:0]      alloc_prs,

    // ---- flush:錯路配出去的 PR ready 狀態要重置 (見說明) ----
    input                       flush
);

    localparam DEPTH  = 1 << PHY_WIDTH;
    localparam RF_NUM = 1 << RF_WIDTH;

    reg [DATA_WIDTH-1:0] regfile [0:DEPTH-1];
    reg                  ready   [0:DEPTH-1];   // 這個 PR 的值算好了沒

    // ---- 讀:組合讀 (同拍 writeback bypass,避免讀到舊值) ----
    assign rd_val1 = (wb_valid && wb_prs == rd_prs1) ? wb_data : regfile[rd_prs1];
    assign rd_val2 = (wb_valid && wb_prs == rd_prs2) ? wb_data : regfile[rd_prs2];

    // ---- ready 查詢 (同拍 writeback 也算 ready) ----
    assign q_rdy1 = ready[q_prs1] | (wb_valid && wb_prs == q_prs1);
    assign q_rdy2 = ready[q_prs2] | (wb_valid && wb_prs == q_prs2);

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            // PR0~31 初始就緒 (architectural 初值,假設為 0),其餘未就緒
            for (i = 0; i < DEPTH; i = i + 1) begin
                regfile[i] <= {DATA_WIDTH{1'b0}};
                ready[i]   <= (i < RF_NUM) ? 1'b1 : 1'b0;
            end
        end else begin
            // 配出新 PR:標記未就緒 (等它被算出來)
            if (alloc_valid) ready[alloc_prs] <= 1'b0;

            // writeback:寫值 + 標記就緒
            if (wb_valid) begin
                regfile[wb_prs] <= wb_data;
                ready[wb_prs]   <= 1'b1;
            end
            // 註:同拍 alloc 與 wb 命中同一 PR 幾乎不可能 (剛配的 PR 不會同拍算完),
            //     若擔心,可讓 wb 優先 (上面順序已是 wb 後寫,自然覆蓋 alloc 的清 0)
        end
    end

endmodule