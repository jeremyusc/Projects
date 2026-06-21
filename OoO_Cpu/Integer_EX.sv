module Integer_EX #(
    parameter DATA_WIDTH = 32,
    parameter PHY_WIDTH  = 7,
    parameter ROB_WIDTH  = 4
)(
    input                       clk, rst,
    input                       flush,

    // =========================================================================
    // 來自 Integer RS 的 ALU 發射 (1 cycle)
    // =========================================================================
    input                       iss_alu_valid,
    input  [3:0]                iss_alu_op,        // 0:ADD 1:SUB
    input  [DATA_WIDTH-1:0]     alu_src1,          // 已從 Phys_RF 讀好的值
    input  [DATA_WIDTH-1:0]     alu_src2,
    input                       iss_alu_rs2_is_imm,
    input  [DATA_WIDTH-1:0]     iss_alu_imm,
    input  [PHY_WIDTH-1:0]      iss_alu_prd,
    input  [ROB_WIDTH-1:0]      iss_alu_rob_idx,
    // branch 資訊 (BNE 才有效)
    input                       iss_alu_is_branch,
    input  [DATA_WIDTH-1:0]     iss_alu_pc,
    input                       iss_alu_pred_taken,
    input  [DATA_WIDTH-1:0]     iss_alu_pred_target,

    // =========================================================================
    // 來自 Integer RS 的 MUL 發射 (4 cycle, non-pipelined)
    // =========================================================================
    input                       iss_mul_valid,
    input  [DATA_WIDTH-1:0]     mul_src1,
    input  [DATA_WIDTH-1:0]     mul_src2,
    input  [PHY_WIDTH-1:0]      iss_mul_prd,
    input  [ROB_WIDTH-1:0]      iss_mul_rob_idx,
    output                      mul_busy,          // MUL 忙碌,RS 不發新 MUL
    //單一CDB MUL結束的時候rs stall
    output                      mul_taking_cdb,

    // =========================================================================
    // 統一 Writeback (CDB) — 給 Phys_RF / RS wakeup / ROB
    // =========================================================================
    output reg                  wb_valid,
    output reg [PHY_WIDTH-1:0]  wb_prs,
    output reg [DATA_WIDTH-1:0] wb_data,
    output reg [ROB_WIDTH-1:0]  wb_rob_idx,
    output reg                  wb_mispredict,     // 給 ROB 存:這條 branch 錯了沒
    output reg [DATA_WIDTH-1:0] wb_correct_pc,     // 給 ROB 存:錯了要跳哪

    // =========================================================================
    // Branch resolution → 給 fetch 立刻更新 BPB/BTB (不等 commit)
    // =========================================================================
    output reg                  br_resolved,
    output reg [DATA_WIDTH-1:0] br_pc,
    output reg                  br_actual_taken,
    output reg [DATA_WIDTH-1:0] br_actual_target
);

    localparam OP_ADD = 4'd0;
    localparam OP_SUB = 4'd1;

    

    // =========================================================================
    // ALU (組合, 1 cycle)
    // =========================================================================
    wire [DATA_WIDTH-1:0] alu_b = iss_alu_rs2_is_imm ? iss_alu_imm : alu_src2;
    reg  [DATA_WIDTH-1:0] alu_result;
    always @(*) begin
        case (iss_alu_op)
            OP_ADD:  alu_result = alu_src1 + alu_b;
            OP_SUB:  alu_result = alu_src1 - alu_b;
            default: alu_result = alu_src1 + alu_b;
        endcase
    end

    // ---- branch 判斷 (BNE: rs1 != rs2 → taken) ----
    wire        br_is        = iss_alu_valid & iss_alu_is_branch;
    wire        actual_taken = (alu_src1 != alu_src2);          // BNE 用減法結果非零
    wire [DATA_WIDTH-1:0] actual_target = iss_alu_pc + iss_alu_imm;
    wire [DATA_WIDTH-1:0] fallthru_pc   = iss_alu_pc + 32'd4;
    // mispredict:方向錯,或方向對但 taken 目標錯
    wire dir_wrong    = (actual_taken != iss_alu_pred_taken);
    wire target_wrong = actual_taken & (actual_target != iss_alu_pred_target);
    wire br_mispred   = br_is & (dir_wrong | target_wrong);
    wire [DATA_WIDTH-1:0] correct_pc = actual_taken ? actual_target : fallthru_pc;

    // =========================================================================
    // MUL (4 cycle non-pipelined):counter + 保存 prd/rob_idx
    // =========================================================================
    reg [2:0]            mul_cnt;     // 4,3,2,1 → 0 完成
    reg                  mul_run;
    reg [DATA_WIDTH-1:0] mul_a, mul_b_r;
    reg [PHY_WIDTH-1:0]  mul_prd_r;
    reg [ROB_WIDTH-1:0]  mul_rob_r;

    wire mul_done = mul_run & (mul_cnt == 3'd1);   // 這拍是最後一拍
    assign mul_busy = mul_run;                     // 跑的時候不收新 MUL
    assign mul_taking_cdb = mul_done;
    wire [DATA_WIDTH-1:0] mul_result = mul_a * mul_b_r; // 簡化:行為級乘法

    // =========================================================================
    // 單 CDB 仲裁:MUL 完成優先,ALU 那拍讓路
    // (ALU 純組合,被擋就這拍別發 → RS 端用 wb 通道是否被 MUL 佔來決定)
    // 這裡簡化:MUL 完成那拍,ALU 結果不上 CDB (RS 該避免同拍發 ALU,或下拍重試)
    // =========================================================================
    always @(posedge clk) begin
        if (rst || flush) begin
            mul_run <= 1'b0;
            mul_cnt <= 0;
        end else begin
            // ---- MUL 啟動 ----
            if (iss_mul_valid && !mul_run) begin
                mul_run   <= 1'b1;
                mul_cnt   <= 3'd4;
                mul_a     <= mul_src1;
                mul_b_r   <= mul_src2;
                mul_prd_r <= iss_mul_prd;
                mul_rob_r <= iss_mul_rob_idx;
            end else if (mul_run) begin
                mul_cnt <= mul_cnt - 3'd1;
                if (mul_cnt == 3'd1) mul_run <= 1'b0;  // 完成,釋放
            end
        end
    end

    // =========================================================================
    // Writeback 選擇 (組合 → 暫存一拍輸出, 避免長路徑)
    // MUL 完成優先;否則 ALU
    // =========================================================================
    always @(posedge clk) begin
        if (rst || flush) begin
            wb_valid    <= 1'b0;
            br_resolved <= 1'b0;
        end else begin
            if (mul_done) begin
                // MUL 上 CDB
                wb_valid      <= 1'b1;
                wb_prs        <= mul_prd_r;
                wb_data       <= mul_result;
                wb_rob_idx    <= mul_rob_r;
                wb_mispredict <= 1'b0;
                wb_correct_pc <= 32'd0;
                br_resolved   <= 1'b0;
            end else if (iss_alu_valid) begin
                // ALU 上 CDB
                wb_valid      <= 1'b1;
                wb_prs        <= iss_alu_prd;
                wb_data       <= alu_result;
                wb_rob_idx    <= iss_alu_rob_idx;
                wb_mispredict <= br_mispred;
                wb_correct_pc <= correct_pc;
                // branch resolution → fetch 更新預測器
                br_resolved      <= br_is;
                br_pc            <= iss_alu_pc;
                br_actual_taken  <= actual_taken;
                br_actual_target <= actual_target;
            end else begin
                wb_valid    <= 1'b0;
                br_resolved <= 1'b0;
            end
        end
    end

endmodule