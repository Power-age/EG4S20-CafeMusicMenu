"""生成 8192x32bit / 2bit-per-pixel 的合并 ROM：8 块 mask，每块 240x68 = 1024 字。
   同时重写 mask_overlay.v 为 2bit 解包（4 档 alpha）。"""
import io
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HDL = Path(r"D:\AAA_University\Anlu\Project\src\user_source\hdl_source")
FONT_R = r"C:\Windows\Fonts\msyh.ttc"
FONT_B = r"C:\Windows\Fonts\msyhbd.ttc"

MW, MH = 240, 68
WORDS_PER_MASK = MW * MH // 16        # 每字 16 像素（2bit）
assert WORDS_PER_MASK == 1020 or True
print("每块字数:", MW * MH / 16)

PAGES = [
    [("手冲埃塞俄比亚", "花香柑橘 干净", "¥28"),
     ("经典卡布奇诺", "奶泡绵密 回甘", "¥26")],
    [("酸种面包", "酵母慢发酵", "¥22"),
     ("黄油可颂", "现烤层次酥脆", "¥18")],
    [("抹茶拿铁", "宇治抹茶 微苦", "¥30"),
     ("巴斯克芝士", "焦香 内心流心", "¥32")],
    [("冰美式", "双份浓缩 清爽", "¥24"),
     ("蓝莓麦芬", "果粒饱满 微甜", "¥20")],
]


def render(name, desc, price):
    img = Image.new("L", (MW, MH), 0)
    d = ImageDraw.Draw(img)
    fn = ImageFont.truetype(FONT_B, 28)
    fd = ImageFont.truetype(FONT_R, 28)
    fp = ImageFont.truetype(FONT_B, 26)
    d.text((4, 1), name, fill=255, font=fn)
    d.text((MW - 4 - d.textlength(price, font=fp), 2), price, fill=255, font=fp)
    d.text((4, 36), desc, fill=255, font=fd)
    q = Image.new("L", (MW, MH), 0)
    src, dst = img.load(), q.load()
    for y in range(MH):
        for x in range(MW):
            v = src[x, y]
            dst[x, y] = 0 if v < 32 else (1 if v < 110 else (2 if v < 200 else 3))
    return q


def pack(q):
    """2bit，每 32bit 字 16 像素：第 i 个像素占 bit[2i+1:2i]。"""
    px = q.load()
    words = []
    for y in range(MH):
        for x0 in range(0, MW, 16):
            w = 0
            for i in range(16):
                w |= (px[x0 + i, y] & 3) << (2 * i)
            words.append(w)
    return words


all_words = []
for page in PAGES:
    for card in range(2):
        name, desc, price = page[card]
        ws = pack(render(name, desc, price))
        assert len(ws) <= 1024, len(ws)
        ws += [0] * (1024 - len(ws))
        all_words += ws
print("总字数:", len(all_words))
assert len(all_words) == 8192

lines = ["WIDTH=32;", "DEPTH=8192;", "", "ADDRESS_RADIX=HEX;", "DATA_RADIX=HEX;", "", "CONTENT BEGIN"]
for i, w in enumerate(all_words):
    lines.append("%04X : %08X;" % (i, w))
lines.append("END;")
io.open(HDL / "txt_all.mif", "w", encoding="ascii", newline="\n").write("\n".join(lines) + "\n")
print("已生成 txt_all.mif（2bit / 8 块 / 8192 字）")

# ---- 重写 overlay：2bit 解包 + 窗口 240x68 ----
src = io.open(HDL / "mask_overlay.v", encoding="utf-8").read()
src = src.replace("""    localparam [10:0] LWX0 = 11'd50,  LWX1 = 11'd290;
    localparam [10:0] RWX0 = 11'd350, RWX1 = 11'd590;
    localparam [9:0]  WY0  = 10'd331, WY1  = 10'd459;""",
"""    localparam [10:0] LWX0 = 11'd50,  LWX1 = 11'd290;
    localparam [10:0] RWX0 = 11'd350, RWX1 = 11'd590;
    localparam [9:0]  WY0  = 10'd335, WY1  = 10'd403;   // 240x68""")
src = src.replace("""    wire [9:0]  waddr = sel[14:5];                 // 除以 32
    wire [4:0]  bidx  = sel[4:0];""",
"""    wire [9:0]  waddr = sel[13:4];                 // 除以 16（每字 16 像素）
    wire [3:0]  bidx  = sel[3:0];""")
src = src.replace("""    reg        hit_q;
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
    end""",
"""    reg        hit_q;
    reg [3:0]  bidx_q;
    always @(posedge clk) begin
        if (rst) begin
            hit_q  <= 1'b0;
            bidx_q <= 4'd0;
        end else begin
            hit_q  <= in_l | in_r;
            bidx_q <= bidx;
        end
    end

    wire [3:0] alpha = (q >> {bidx_q, 1'b0}) & 4'd3;   // 2bit / 像素

    always @(posedge clk) begin
        if (rst)             rgb_out <= 24'd0;
        else if (!hit_q)     rgb_out <= rgb_in;
        else                 rgb_out <= (rgb_in * (4 - alpha) + TEXT_COLOR * alpha) >> 2;
    end""")
io.open(HDL / "mask_overlay.v", "w", encoding="utf-8", newline="\n").write(src)
print("mask_overlay.v 已改为 2bit / 240x68")
