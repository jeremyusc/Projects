module Memory_RS #(
    parameter DATA_WIDTH = 32,
    parameter PHY_WIDTH  = 7,
    parameter ROB_WIDTH  = 4,
    parameter RS_WIDTH   = 3,
    parameter RS_NUM     = 8
)(
    input                       clk, rst,
    input                       flush,

    // ---- dispatch (LW/SW 進來) ----
    input                       disp_valid,
    input                       disp_is_store,      // 0:load 1:store
    input  [PHY_WIDTH-1:0]      disp_prs1,          // base address 來源
    input                       disp_rdy1,
    input  [PHY_WIDTH-1:0]      disp_prs2,          // store data 來源 (load 不用)
    input                       disp_rdy2,
    input  [DATA_WIDTH-1:0]     disp_imm,           // offset
    input  [PHY_WIDTH-1:0]      disp_prd,           // load 的 dest PR (store 不用)
    input  [ROB_WIDTH-1:0]      disp_rob_idx,
    output                      rs_full,

    // ---- writeback snoop (wakeup) ----
    input                       wb_valid,
    input  [PHY_WIDTH-1:0]      wb_prs,

    // ---- 讀 RF (發射時算位址 / 拿 store data) ----
    output [PHY_WIDTH-1:0]      rd_prs1,            // base
    output [PHY_WIDTH-1:0]      rd_prs2,            // store data
    input  [DATA_WIDTH-1:0]     rd_val1,            // base 值
    input  [DATA_WIDTH-1:0]     rd_val2,            // store data 值

    // ---- 發射:算好位址,送 LQ (load) 或 SQ (store) ----
    output                      iss_valid,
    output                      iss_is_store,
    output [DATA_WIDTH-1:0]     iss_addr,           // 算好的記憶體位址 rs1 + imm
    output [DATA_WIDTH-1:0]     iss_store_data,     // store 要寫的資料 (store 才有效)
    output [PHY_WIDTH-1:0]      iss_prd,            // load 的 dest PR
    output [ROB_WIDTH-1:0]      iss_rob_idx,
    input                       lq_ready,   // LQ 有空間收 load
    input                       sq_ready    // SQ 有空間收 store
);

    reg                  busy    [0:RS_NUM-1];
    reg                  is_store[0:RS_NUM-1];
    reg [PHY_WIDTH-1:0]  prs1    [0:RS_NUM-1];
    reg [PHY_WIDTH-1:0]  prs2    [0:RS_NUM-1];
    reg                  rdy1    [0:RS_NUM-1];
    reg                  rdy2    [0:RS_NUM-1];
    reg [DATA_WIDTH-1:0] imm     [0:RS_NUM-1];
    reg [PHY_WIDTH-1:0]  prd     [0:RS_NUM-1];
    reg [ROB_WIDTH-1:0]  rob_idx [0:RS_NUM-1];

    integer i;

    // ---- entry ready:load 只等 base(rdy1);store 等 base+data(rdy1&rdy2) ----
    wire [RS_NUM-1:0] entry_ready;
    genvar g;
    generate
        for (g = 0; g < RS_NUM; g = g + 1) begin : RDY
            assign entry_ready[g] = busy[g] & rdy1[g]
                      & (is_store[g] ? rdy2[g]    : 1'b1)   // operand 好了
                      & (is_store[g] ? sq_ready   : lq_ready); // 目標 queue 有空間
        end
    endgenerate

    // ---- 找空 entry ----
    reg [RS_WIDTH-1:0] free_idx; reg has_free;
    always @(*) begin
        has_free = 1'b0; free_idx = 0;
        for (i = RS_NUM-1; i >= 0; i = i - 1)
            if (!busy[i]) begin has_free = 1'b1; free_idx = i[RS_WIDTH-1:0]; end
    end
    assign rs_full = ~has_free;

    // ---- 選一個 ready entry 發射 (in-order 較安全:選最老的;這裡先用最低位) ----
    reg [RS_WIDTH-1:0] sel_idx; reg sel_hit;
    always @(*) begin
        sel_hit = 1'b0; sel_idx = 0;
        for (i = RS_NUM-1; i >= 0; i = i - 1)
            if (entry_ready[i]) begin sel_hit = 1'b1; sel_idx = i[RS_WIDTH-1:0]; end
    end

    // ---- 發射:讀 RF 算位址 ----
    assign rd_prs1 = prs1[sel_idx];
    assign rd_prs2 = prs2[sel_idx];

    assign mem_ready  = (is_store[sel_idx]) ? sq_ready : lq_ready;

    assign iss_valid      = sel_hit & mem_ready;
    assign iss_is_store   = is_store[sel_idx];
    assign iss_addr       = rd_val1 + imm[sel_idx];   // AGU: base + offset
    assign iss_store_data = rd_val2;                  // store data (load 時忽略)
    assign iss_prd        = prd[sel_idx];
    assign iss_rob_idx    = rob_idx[sel_idx];

    always @(posedge clk) begin
        if (rst || flush) begin
            for (i = 0; i < RS_NUM; i = i + 1) busy[i] <= 1'b0;
        end else begin
            // wakeup
            if (wb_valid) begin
                for (i = 0; i < RS_NUM; i = i + 1) begin
                    if (busy[i] && prs1[i] == wb_prs) rdy1[i] <= 1'b1;
                    if (busy[i] && prs2[i] == wb_prs) rdy2[i] <= 1'b1;
                end
            end

            // dispatch
            if (disp_valid && has_free) begin
                busy    [free_idx] <= 1'b1;
                is_store[free_idx] <= disp_is_store;
                prs1    [free_idx] <= disp_prs1;
                prs2    [free_idx] <= disp_prs2;
                rdy1    [free_idx] <= disp_rdy1 | (wb_valid && wb_prs == disp_prs1);
                rdy2    [free_idx] <= disp_rdy2 | (wb_valid && wb_prs == disp_prs2);
                imm     [free_idx] <= disp_imm;
                prd     [free_idx] <= disp_prd;
                rob_idx [free_idx] <= disp_rob_idx;
            end

            // 發射後清空
            if (iss_valid) busy[sel_idx] <= 1'b0;
        end
    end

endmodule