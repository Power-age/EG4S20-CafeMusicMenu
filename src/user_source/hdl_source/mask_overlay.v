// 卡内文字 mask 叠加（1bit / 8 块合一 ROM / 按页号选择）
// 存储：8192 x 32bit（每字 32 像素），索引 = {mask_idx[2:0], word_addr[9:0]}
//   mask_idx = {page[1:0], card}  card: 0=左卡 1=右卡
// 位序：bit0 = 该字第一个像素（从左到右）
`timescale 1ns/1ps

module mask_overlay (
    input             clk,
    input             rst,
    input             de,
    input      [10:0] x,
    input      [9:0]  y,
    input      [23:0] rgb_in,
    input             panel_vis,
    input             mask_en,
    input      [1:0]  page,          // 当前页 0~3
    input      [9:0]  slide_l,
    input      [9:0]  slide_r,
    output reg [23:0] rgb_out
);
    localparam [10:0] LWX0 = 11'd60,  LWX1 = 11'd260;   // 200 宽，卡片内居中
    localparam [10:0] RWX0 = 11'd360, RWX1 = 11'd560;
    localparam [9:0]  WY0  = 10'd340, WY1  = 10'd420;   // 80 高，必须与 ROM 行数一致
    localparam [23:0] TEXT_COLOR = 24'h3A2A1E;   // 深棕（卡片是米白底）

    wire in_y = (y >= WY0) && (y < WY1);
    wire [10:0] lx = x - LWX0 + slide_l;
    wire [10:0] rx = x - RWX0 - slide_r;
    wire in_l = mask_en && !panel_vis && de && in_y && (x >= LWX0) && (x < LWX1) && (lx < 11'd200)
              ;
    wire in_r = mask_en && !panel_vis && de && in_y && (x >= RWX0) && (x < RWX1) && (rx < 11'd200)
              ;

    wire [9:0]  ly  = y - WY0;
    wire [13:0] lin = ly * 14'd200 + {4'd0, lx};   // 最大 15999，需 14 位
    wire [13:0] rin = ly * 14'd200 + {4'd0, rx};
    wire [13:0] sel = in_l ? lin : rin;
    wire [8:0]  waddr = sel[13:5];                 // 除以 32（每字 32 像素）
    wire [4:0]  bidx  = sel[4:0];
    wire [2:0]  midx  = {page, ~in_l};             // 左卡=0 右卡=1
    wire [11:0] addr  = {midx, waddr};             // 每块 512 字

    wire [31:0] q;
`ifdef MASK_SIM
    reg [31:0] mem [0:4095];
    initial $readmemh("../../user_source/hdl_source/txt_all.mif", mem);
    reg [31:0] q_r;
    always @(posedge clk) if (de) q_r <= mem[addr];
    assign q = q_r;
`else
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(32), .ADDR_WIDTH_A(12), .DATA_DEPTH_A(4096),
        .DATA_WIDTH_B(32), .ADDR_WIDTH_B(12), .DATA_DEPTH_B(4096),
        .MODE("SP"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("OFF"), .INIT_FILE("../../user_source/hdl_source/txt_all.mif"),
        .FILL_ALL("NONE")
    ) mask_ram_inst (
        .dia(32'd0), .addra(addr), .cea(de), .ocea(1'b0),
        .clka(clk), .wea(1'b0), .rsta(1'b0), .bea(1'b0),
        .dib(32'd0), .addrb(12'd0), .ceb(1'b0), .oceb(1'b0),
        .clkb(clk), .web(1'b0), .rstb(1'b0), .beb(1'b0),
        .doa(q), .dob()
    );
`endif

    reg        hit_q;
    reg [4:0]  bidx_q;
    always @(posedge clk) begin
        if (rst) begin
            hit_q  <= 1'b0;
            bidx_q <= 5'd0;
        end else begin
            hit_q  <= in_l | in_r;
            bidx_q <= bidx;
        end
    end

    wire on = (q >> bidx_q) & 1'b1;     // 1bit / 像素

    always @(posedge clk) begin
        if (rst)             rgb_out <= 24'd0;
        else if (!hit_q)     rgb_out <= rgb_in;
        else if (on)         rgb_out <= TEXT_COLOR;
        else                 rgb_out <= rgb_in;
    end
endmodule
