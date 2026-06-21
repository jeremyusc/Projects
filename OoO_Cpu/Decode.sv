module Decode #(
    parameter ADDR       = 10,
    parameter DATA_WIDTH = 32,
    parameter RF_WIDTH = 5
)(
    input clk,
    input rst,
    input   [DATA_WIDTH-1:0] din,
    output reg   [RF_WIDTH-1:0] dec_rs1,          // 暫存器編號
    output reg   [RF_WIDTH-1:0] dec_rs2,
    output reg   [RF_WIDTH-1:0] dec_rd,
    output reg   [31:0] dec_imm,          // 解碼後的立即值 (Sign-extended)
    output reg   [3:0]  dec_alu_op,        // 0:ADD 1:SUB 2:MUL 3:MEM_ADDR
    output reg   [1:0]  dec_rs_type,       // 00:Adder 01:Multiplier 10:Load 11:Store
    ////Branch
    output reg dec_is_branch,    // 是否為跳躍指令
    ////MEMORY
    output reg dec_valid,
    output reg dec_is_store,
    /// RENAME
    output reg dec_use_rs1,///imm => not use => no need physical register
    output reg dec_use_rs2,
    output reg dec_use_rd,
    output reg dec_rs2_is_imm
);

// Instruction encoding:
//   [31:26] opcode   [25:21] rd/rs2  [20:16] rs1  [15:11] rs2  [15:0] imm (16-bit signed)
localparam NOP  = 6'd0;
localparam ADD  = 6'd1;
localparam SUB  = 6'd2;
localparam MUL  = 6'd3;
localparam LW   = 6'd4;
localparam SW   = 6'd5;
localparam ADDI = 6'd6;
localparam BNE  = 6'd7;

wire [5:0] opcode = din[31:26];

always @(*) begin
    dec_rs1         = 5'd0;
    dec_rs2         = 5'd0;
    dec_rd          = 5'd0;
    dec_imm         = 32'd0;
    dec_alu_op      = 4'd0;
    dec_rs2_is_imm = 1'b0;
    dec_is_branch   = 1'b0;
    dec_rs_type     = 2'b00;

    dec_valid       = 1'b0;
    dec_is_store    = 1'b0;
    dec_use_rs1     = 1'b0;
    dec_use_rs2     = 1'b0;
    dec_use_rd      = 1'b0;

    case (opcode)
        NOP: ; // 全部維持預設

        ADD: begin
            dec_rd      = din[25:21];
            dec_rs1     = din[20:16];
            dec_rs2     = din[15:11];
            dec_alu_op  = 4'd0;       // ADD
            dec_rs_type = 2'b00;
            //renaming
            dec_use_rs1 = 1'b1;
            dec_use_rs2 = 1'b1;
            dec_use_rd = 1'b1;
            dec_valid = 1'b1;
            
        end

        SUB: begin
            dec_rd      = din[25:21];
            dec_rs1     = din[20:16];
            dec_rs2     = din[15:11];
            dec_alu_op  = 4'd1;       // SUB
            dec_rs_type = 2'b00;
            //renaming
            dec_use_rs1 = 1'b1;
            dec_use_rs2 = 1'b1;
            dec_use_rd = 1'b1;
            dec_valid = 1'b1;
        end

        MUL: begin
            dec_rd      = din[25:21];
            dec_rs1     = din[20:16];
            dec_rs2     = din[15:11];
            dec_alu_op  = 4'd2;       // MUL
            dec_rs_type = 2'b01;
            //renaming
            dec_use_rs1 = 1'b1;
            dec_use_rs2 = 1'b1;
            dec_use_rd = 1'b1;
            dec_valid = 1'b1;
        end

        // LW rd, imm(rs1)  →  rd = Mem[rs1 + imm]
        LW: begin
            dec_rd          = din[25:21];
            dec_rs1         = din[20:16];
            dec_imm         = {{16{din[15]}}, din[15:0]};  // sign-extend 16-bit
            dec_alu_op      = 4'd3;   // 計算記憶體位址 (base + offset)
            dec_rs_type     = 2'b10;///LW
            //renaming
            dec_use_rs1 = 1'b1;
            dec_use_rs2 = 1'b0;
            dec_use_rd = 1'b1;
            dec_rs2_is_imm =1'b1;
            dec_valid = 1'b1;
        end

        // SW rs2, imm(rs1)  →  Mem[rs1 + imm] = rs2
        SW: begin
            dec_rs2         = din[25:21];  // 要寫入的資料來源
            dec_rs1         = din[20:16];  // base address
            dec_imm         = {{16{din[15]}}, din[15:0]};
            dec_alu_op      = 4'd3;
            
            dec_rs_type     = 2'b11;///SW
            //renaming
            dec_use_rs1 = 1'b1;
            dec_use_rs2 = 1'b1;
            dec_use_rd = 1'b0;
            dec_rs2_is_imm = 1'b0;
            dec_is_store = 1'b1;
            dec_valid = 1'b1;
        end

        // ADDI rd, rs1, imm  →  rd = rs1 + imm
        ADDI: begin
            dec_rd          = din[25:21];
            dec_rs1         = din[20:16];
            dec_imm         = {{16{din[15]}}, din[15:0]};
            dec_alu_op      = 4'd0;   // ADD
            dec_rs_type     = 2'b00;
            //renaming
            dec_use_rs1 = 1'b1;
            dec_use_rs2 = 1'b0;
            dec_use_rd = 1'b1;
            dec_rs2_is_imm =1'b1;
            dec_valid = 1'b1;
        end

        // BNE rs1, rs2, imm  →  if (rs1 != rs2) PC += imm<<1
        BNE: begin
            dec_rs1         = din[25:21];
            dec_rs2         = din[20:16];
            dec_imm         = {{15{din[15]}}, din[15:0], 1'b0};  // word-aligned offset
            dec_alu_op      = 4'd1;   // SUB 比較是否為零
            dec_is_branch   = 1'b1;
            dec_rs_type     = 2'b00;
            //renaming
            dec_use_rs1 = 1'b1;
            dec_use_rs2 = 1'b1;
            dec_use_rd = 1'b0;
            dec_valid = 1'b1;
        end

        default: ;
    endcase
end

endmodule
