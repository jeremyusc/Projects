module Free_list#(
    parameter ADDR       = 10,
    parameter DATA_WIDTH = 32,
    parameter RF_WIDTH = 5,
    parameter PHY_WIDTH = 7
)(
    input clk,rst,
    ///rename interface
    input                   dec_use_rd,
    input  [RF_WIDTH-1:0]   dec_rd,//判斷 r0,跟 RAT 的 rename_alloc 一致
    
    input issue_ready,
    output  [PHY_WIDTH-1:0] free_phy_reg,

    /////ROB interface
    input                   rob_commit_valid,
    input [PHY_WIDTH-1:0]   rob_commit_old_reg,
    input                   rob_commit_use_rd, // 加進來:store/branch 不 push
    input  [RF_WIDTH-1:0]   rob_commit_rd,     // 加進來:判斷 r0
    /////mispredict recovery
    input                       branch_mispredict,
    output full, empty
);
localparam DEPTH = 1 << PHY_WIDTH; //初始128
localparam RF_NUM  = 1 << RF_WIDTH;   // 32，初始被 ARF 佔用

reg [PHY_WIDTH-1:0] fifo [0:DEPTH-1];

reg [PHY_WIDTH:0] w_ptr,r_ptr,r_ptr_commit;

wire alloc_en = dec_use_rd & (dec_rd != 0);
wire commit_write = rob_commit_use_rd & (rob_commit_rd != 0);
////比對同一個rd 空/滿 enbale
wire r_en = alloc_en & !empty & issue_ready;
wire w_en = commit_write && rob_commit_valid & !full;

assign full = (w_ptr[PHY_WIDTH]!=r_ptr[PHY_WIDTH]) && 
                (w_ptr[PHY_WIDTH-1:0] == r_ptr[PHY_WIDTH-1:0]);
assign empty = (w_ptr ==r_ptr);
assign free_phy_reg = fifo[r_ptr[PHY_WIDTH-1:0]];

integer i;
always @(posedge clk) begin
    if (rst) begin
        r_ptr <= 0;
        r_ptr_commit <= 0;
        w_ptr <= DEPTH - RF_NUM;
        for (i = 0; i < DEPTH - RF_NUM; i = i + 1)
            fifo[i] <= i[PHY_WIDTH-1:0] + RF_NUM;
    end else begin
        ////回收pr
        if (w_en) begin
            fifo[w_ptr[PHY_WIDTH-1:0]] <= rob_commit_old_reg;
            w_ptr <= w_ptr + 1;
        end
        ////mispredict
        if(branch_mispredict) 
            r_ptr <= r_ptr_commit;
        else if(r_en)
            r_ptr <= r_ptr + 1;
        ///分配
        if (w_en) r_ptr_commit <= r_ptr_commit + 1;
    end
end



endmodule