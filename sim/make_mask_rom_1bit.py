import io
from pathlib import Path

SRC = Path(r"D:\AAA_University\Anlu\Project\doc\TF卡\sub_mask_v2")
HDL = Path(r"D:\AAA_University\Anlu\Project\src\user_source\hdl_source")

# 1) 生成 8192x32bit 合并 ROM（1bit/像素，8 块 mask 按 [页*2+左右] 连续排列）
order = [(p, k) for p in range(1, 5) for k in (1, 2)]   # TXT11,TXT12,TXT21,...
words = []
for page, k in order:
    raw = (SRC / ("TXT%d%d.BIN" % (page, k))).read_bytes()
    assert len(raw) == 240 * 128 // 4
    # 2bit -> 1bit：>=2 记 1
    bits = []
    for b in raw:
        for s in (0, 2, 4, 6):
            bits.append(1 if ((b >> s) & 3) >= 2 else 0)
    assert len(bits) == 240 * 128
    # 打包成 32bit 字（bit0 是该字第一个像素）
    for i in range(0, len(bits), 32):
        w = 0
        for j in range(32):
            if bits[i + j]:
                w |= 1 << j
        words.append(w)
print("总字数:", len(words))
assert len(words) == 7680, len(words)     # 8 x 960
words += [0] * (8192 - len(words))         # 补零到 8192（BRAM 深度）

lines = ["WIDTH=32;", "DEPTH=8192;", "", "ADDRESS_RADIX=HEX;", "DATA_RADIX=HEX;", "", "CONTENT BEGIN"]
for i, w in enumerate(words):
    lines.append("%04X : %08X;" % (i, w))
lines.append("END;")
io.open(HDL / "txt_all.mif", "w", encoding="ascii", newline="\n").write("\n".join(lines) + "\n")
print("已生成 txt_all.mif")

# 2) 重写 mask_overlay.v（1bit + 单 ROM + 页号选择）
mod = r'''// 卡内文字 mask 叠加（1bit / 8 块合一 ROM / 按页号选择）
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
    localparam [10:0] LWX0 = 11'd50,  LWX1 = 11'd290;
    localparam [10:0] RWX0 = 11'd350, RWX1 = 11'd590;
    localparam [9:0]  WY0  = 10'd331, WY1  = 10'd459;
    localparam [23:0] TEXT_COLOR = 24'hF4EDE2;

    wire in_y = (y >= WY0) && (y < WY1);
    wire [10:0] lx = x - LWX0 + slide_l;
    wire [10:0] rx = x - RWX0 - slide_r;
    wire in_l = mask_en && !panel_vis && de && in_y && (x >= LWX0) && (x < LWX1) && (lx < 11'd240);
    wire in_r = mask_en && !panel_vis && de && in_y && (x >= RWX0) && (x < RWX1) && (rx < 11'd240);

    wire [9:0]  ly  = y - WY0;
    wire [10:0] lin = {1'b0, ly} * 11'd240 + lx;
    wire [10:0] rin = {1'b0, ly} * 11'd240 + rx;
    wire [10:0] sel = in_l ? lin : rin;
    wire [9:0]  waddr = sel[14:5];                 // 除以 32
    wire [4:0]  bidx  = sel[4:0];
    wire [2:0]  midx  = {page, ~in_l};             // 左卡=0 右卡=1
    wire [12:0] addr  = {midx, waddr};

    wire [31:0] q;
`ifdef MASK_SIM
    reg [31:0] mem [0:8191];
    initial $readmemh("../../user_source/hdl_source/txt_all.mif", mem);
    reg [31:0] q_r;
    always @(posedge clk) if (de) q_r <= mem[addr];
    assign q = q_r;
`else
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(32), .ADDR_WIDTH_A(13), .DATA_DEPTH_A(8192),
        .DATA_WIDTH_B(32), .ADDR_WIDTH_B(13), .DATA_DEPTH_B(8192),
        .MODE("SP"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("OFF"), .INIT_FILE("../../user_source/hdl_source/txt_all.mif"),
        .FILL_ALL("NONE")
    ) mask_ram_inst (
        .dia(32'd0), .addra(addr), .cea(de), .ocea(1'b0),
        .clka(clk), .wea(1'b0), .rsta(1'b0), .bea(1'b0),
        .dib(32'd0), .addrb(13'd0), .ceb(1'b0), .oceb(1'b0),
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

    wire on = (q >> bidx_q) & 1'b1;

    always @(posedge clk) begin
        if (rst)                 rgb_out <= 24'd0;
        else if (!hit_q)         rgb_out <= rgb_in;
        else if (on)             rgb_out <= TEXT_COLOR;
        else                     rgb_out <= rgb_in;
    end
endmodule
'''
io.open(HDL / "mask_overlay.v", "w", encoding="utf-8", newline="\n").write(mod)
print("mask_overlay.v 已重写（1bit / 单 ROM / 页号选择）")
