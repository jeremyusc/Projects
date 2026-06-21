module Integer_RS #(
    parameter DATA_WIDTH = 32,
    parameter PHY_WIDTH  = 7,
    parameter ROB_WIDTH  = 4,
    parameter RS_WIDTH   = 3,            // 8 個 entry
    parameter RS_NUM     = 8
)(
    input                       clk, rst,
    input                       flush,

    // ---- dispatch (rename 完一條 integer 指令進來) ----
    input                       disp_valid,
    input  [3:0]                disp_alu_op,    // 0:ADD 1:SUB 2:MUL
    input                       disp_is_mul,    // rs_type==Multiplier      rs_type = 01
    input  [PHY_WIDTH-1:0]      disp_prs1, disp_prs2,
    input                       disp_rdy1, disp_rdy2,  // dispatch 當下 source 就緒沒 (查 Phys_RF)
    input                       disp_rs2_is_imm,
    input  [DATA_WIDTH-1:0]     disp_imm,
    input  [PHY_WIDTH-1:0]      disp_prd,
    input  [ROB_WIDTH-1:0]      disp_rob_idx,
    output                      rs_full,

    // ---- writeback snoop (wakeup) ----
    input                       wb_valid,
    input  [PHY_WIDTH-1:0]      wb_prs,

    // ---- 發射給 ALU (1 cycle) ----
    output                      iss_alu_valid,
    output [3:0]                iss_alu_op,
    output [PHY_WIDTH-1:0]      iss_alu_prs1, iss_alu_prs2,
    output                      iss_alu_rs2_is_imm,
    output [DATA_WIDTH-1:0]     iss_alu_imm,
    output [PHY_WIDTH-1:0]      iss_alu_prd,
    output [ROB_WIDTH-1:0]      iss_alu_rob_idx,

    // ---- 發射給 MUL (4 cycle, non-pipelined) ----
    output                      iss_mul_valid,
    output [PHY_WIDTH-1:0]      iss_mul_prs1, iss_mul_prs2,
    output [PHY_WIDTH-1:0]      iss_mul_prd,
    output [ROB_WIDTH-1:0]      iss_mul_rob_idx,
    input                       mul_busy,      // MUL 忙碌中,不能再發
    input                       mul_taking_cdb,

    //  ------branch
    input                       disp_is_branch,
    input  [DATA_WIDTH-1:0]     disp_pc,
    input                       disp_pred_taken,
    input  [DATA_WIDTH-1:0]     disp_pred_target,

    output                      iss_alu_is_branch,
    output [DATA_WIDTH-1:0]     iss_alu_pc,
    output                      iss_alu_pred_taken,
    output [DATA_WIDTH-1:0]     iss_alu_pred_target
);

    // ---- entry 欄位 ----
    reg                  busy   [0:RS_NUM-1];
    reg [3:0]            alu_op [0:RS_NUM-1];
    reg                  is_mul [0:RS_NUM-1];
    reg [PHY_WIDTH-1:0]  prs1   [0:RS_NUM-1];
    reg [PHY_WIDTH-1:0]  prs2   [0:RS_NUM-1];
    reg                  rdy1   [0:RS_NUM-1];
    reg                  rdy2   [0:RS_NUM-1];
    reg                  r2_imm [0:RS_NUM-1];
    reg [DATA_WIDTH-1:0] imm    [0:RS_NUM-1];
    reg [PHY_WIDTH-1:0]  prd    [0:RS_NUM-1];
    reg [ROB_WIDTH-1:0]  rob_idx[0:RS_NUM-1];
    reg                  is_branch  [0:RS_NUM-1];
    reg [DATA_WIDTH-1:0] pc         [0:RS_NUM-1];
    reg                  pred_taken [0:RS_NUM-1];
    reg [DATA_WIDTH-1:0] pred_target[0:RS_NUM-1];

    integer i;

    // ---- entry 是否就緒 (rs2_is_imm 的指令不用等 rs2) ----
    wire [RS_NUM-1:0] entry_ready;
    genvar g;
    generate
        for (g = 0; g < RS_NUM; g = g + 1) begin : RDY
            assign entry_ready[g] = busy[g] & rdy1[g] & (rdy2[g] | r2_imm[g]);
        end
    endgenerate

    // ---- 找一個空 entry 給 dispatch (最低位優先) ----
    reg [RS_WIDTH-1:0] free_idx;
    reg                has_free;
    always @(*) begin
        has_free = 1'b0;
        free_idx = 0;
        for (i = RS_NUM-1; i >= 0; i = i - 1)
            if (!busy[i]) begin 
                has_free = 1'b1; 
                free_idx = i[RS_WIDTH-1:0]; 
            end
    end
    assign rs_full = ~has_free;/////如果rs_full就是全部entry都沒能把has_free拉高=>全滿

    // ---- 選一個 ready 的 ALU entry / MUL entry 發射 (各選最低位) ----
    reg [RS_WIDTH-1:0] alu_idx; reg alu_hit;
    reg [RS_WIDTH-1:0] mul_idx; reg mul_hit;

/////所以busy是RS這格有沒有指令, 如果有的話, 再看rs1,rs2準備好了沒. 
//////其中rs2如果是放imm,因爲不需要計算所以可以直接說這個rs的entry好了, 可以拿去alu計算最終rd了
    always @(*) begin
        alu_hit = 1'b0; alu_idx = 0;
        mul_hit = 1'b0; mul_idx = 0;
        for (i = RS_NUM-1; i >= 0; i = i - 1) begin
            if (entry_ready[i] && !is_mul[i]) begin 
                alu_hit = 1'b1; 
                alu_idx = i[RS_WIDTH-1:0]; 
            end
            if (entry_ready[i] &&  is_mul[i]) begin 
                mul_hit = 1'b1; 
                mul_idx = i[RS_WIDTH-1:0]; 
            end
        end
    end
/////////////////////////////////////////
    assign iss_alu_valid      = alu_hit & ~mul_taking_cdb;
    assign iss_alu_op         = alu_op[alu_idx];
    assign iss_alu_prs1       = prs1[alu_idx];
    assign iss_alu_prs2       = prs2[alu_idx];
    assign iss_alu_rs2_is_imm = r2_imm[alu_idx];
    assign iss_alu_imm        = imm[alu_idx];
    assign iss_alu_prd        = prd[alu_idx];
    assign iss_alu_rob_idx    = rob_idx[alu_idx];

    assign iss_mul_valid      = mul_hit & ~mul_busy;////ALU 每拍都會算, 所以不需要額外的Bussy
    assign iss_mul_prs1       = prs1[mul_idx];
    assign iss_mul_prs2       = prs2[mul_idx];
    assign iss_mul_prd        = prd[mul_idx];
    assign iss_mul_rob_idx    = rob_idx[mul_idx];

    //branch
    assign iss_alu_is_branch   = is_branch[alu_idx];
    assign iss_alu_pc          = pc[alu_idx];
    assign iss_alu_pred_taken  = pred_taken[alu_idx];
    assign iss_alu_pred_target = pred_target[alu_idx];


    always @(posedge clk) begin
        if (rst || flush) begin
            for (i = 0; i < RS_NUM; i = i + 1) 
                busy[i] <= 1'b0;
        end else begin
            // ---- wakeup:snoop writeback,把等這個 PR 的 entry 設 ready ----
            if (wb_valid) begin
                for (i = 0; i < RS_NUM; i = i + 1) begin
                    if (busy[i] && prs1[i] == wb_prs) 
                        rdy1[i] <= 1'b1;

                    if (busy[i] && prs2[i] == wb_prs) 
                        rdy2[i] <= 1'b1;
                end
            end

            // ---- dispatch:寫進空 entry ----
            if (disp_valid && has_free) begin
                busy   [free_idx] <= 1'b1;
                alu_op [free_idx] <= disp_alu_op;
                is_mul [free_idx] <= disp_is_mul;
                prs1   [free_idx] <= disp_prs1;
                prs2   [free_idx] <= disp_prs2;
                // dispatch 當下若 source 已就緒,或同拍 wb 命中,直接設 ready
                rdy1   [free_idx] <= disp_rdy1 | (wb_valid && wb_prs == disp_prs1);
                rdy2   [free_idx] <= disp_rdy2 | (wb_valid && wb_prs == disp_prs2);
                r2_imm [free_idx] <= disp_rs2_is_imm;
                imm    [free_idx] <= disp_imm;
                prd    [free_idx] <= disp_prd;
                rob_idx[free_idx] <= disp_rob_idx;

                is_branch  [free_idx] <= disp_is_branch;
                pc         [free_idx] <= disp_pc;
                pred_taken [free_idx] <= disp_pred_taken;
                pred_target[free_idx] <= disp_pred_target;
            end

            // ---- 發射後清空 entry ----
            if (iss_alu_valid) 
                busy[alu_idx] <= 1'b0;

            if (iss_mul_valid) 
                busy[mul_idx] <= 1'b0;
        end
    end

endmodule