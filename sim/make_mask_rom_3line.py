"""1bit / 240x128 / 三行版式（名称 + 两行介绍 + 价格），8 块合一个 8192x32bit ROM。"""
import io
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HDL = Path(r"D:\AAA_University\Anlu\Project\src\user_source\hdl_source")
FONT_R = r"C:\Windows\Fonts\msyh.ttc"
FONT_B = r"C:\Windows\Fonts\msyhbd.ttc"

MW, MH = 240, 128
WORDS = MW * MH // 32          # 1bit：每字 32 像素
print("每块字数:", WORDS)

PAGES = [
    [("手冲埃塞俄比亚", "花香与柑橘", "口感干净", "¥28"),
     ("经典卡布奇诺", "奶泡绵密", "醇厚回甘", "¥26")],
    [("酸种面包", "天然酵母", "慢发酵", "¥22"),
     ("黄油可颂", "当日现烤", "层次酥脆", "¥18")],
    [("抹茶拿铁", "宇治抹茶", "微苦回甘", "¥30"),
     ("巴斯克芝士", "焦香表层", "内心流心", "¥32")],
    [("冰美式", "双份浓缩", "清爽利落", "¥24"),
     ("蓝莓麦芬", "果粒饱满", "微甜不腻", "¥20")],
]


def render(name, d1, d2, price):
    img = Image.new("L", (MW, MH), 0)
    d = ImageDraw.Draw(img)
    fn = ImageFont.truetype(FONT_B, 30)
    fd = ImageFont.truetype(FONT_R, 24)
    fp = ImageFont.truetype(FONT_B, 26)
    d.text((4, 2), name, fill=255, font=fn)
    d.text((MW - 4 - d.textlength(price, font=fp), 6), price, fill=255, font=fp)
    d.text((4, 42), d1, fill=255, font=fd)
    d.text((4, 74), d2, fill=255, font=fd)
    return img


def pack(img):
    """连续打包：按行优先展平成 bit 流，每 32bit 一个字（与 overlay 的 ly*240+lx 一致）"""
    px = img.load()
    bits = []
    for y in range(MH):
        for x in range(MW):
            bits.append(1 if px[x, y] > 110 else 0)
    words = []
    for i in range(0, len(bits), 32):
        chunk = bits[i:i + 32]
        chunk += [0] * (32 - len(chunk))
        w = 0
        for j, b in enumerate(chunk):
            if b:
                w |= 1 << j
        words.append(w)
    return words


all_words = []
for page in PAGES:
    for card in range(2):
        ws = pack(render(*page[card]))
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
print("已生成 txt_all.mif（1bit / 240x128 / 三行）")

# ---- overlay：1bit 解包 + 窗口 240x128 ----
s = io.open(HDL / "mask_overlay.v", encoding="utf-8").read()
s = s.replace("""    localparam [9:0]  WY0  = 10'd335, WY1  = 10'd403;   // 240x68""",
"""    localparam [9:0]  WY0  = 10'd334, WY1  = 10'd462;   // 240x128（三行版式）""")
s = s.replace("""    wire [9:0]  waddr = sel[13:4];                 // 除以 16（每字 16 像素）
    wire [3:0]  bidx  = sel[3:0];""",
"""    wire [9:0]  waddr = sel[14:5];                 // 除以 32（每字 32 像素，1bit）
    wire [4:0]  bidx  = sel[4:0];""")
s = s.replace("""    reg        hit_q;
    reg [3:0]  bidx_q;
    always @(posedge clk) begin
        if (rst) begin
            hit_q  <= 1'b0;
            bidx_q <= 4'd0;
        end else begin""",
"""    reg        hit_q;
    reg [4:0]  bidx_q;
    always @(posedge clk) begin
        if (rst) begin
            hit_q  <= 1'b0;
            bidx_q <= 5'd0;
        end else begin""")
s = s.replace("""    wire [3:0] alpha = (q >> {bidx_q, 1'b0}) & 4'd3;   // 2bit / 像素

    always @(posedge clk) begin
        if (rst)             rgb_out <= 24'd0;
        else if (!hit_q)     rgb_out <= rgb_in;
        else                 rgb_out <= (rgb_in * (4 - alpha) + TEXT_COLOR * alpha) >> 2;
    end""",
"""    wire on = (q >> bidx_q) & 1'b1;     // 1bit / 像素

    always @(posedge clk) begin
        if (rst)             rgb_out <= 24'd0;
        else if (!hit_q)     rgb_out <= rgb_in;
        else if (on)         rgb_out <= TEXT_COLOR;
        else                 rgb_out <= rgb_in;
    end""")
io.open(HDL / "mask_overlay.v", "w", encoding="utf-8", newline="\n").write(s)
print("mask_overlay.v 已改为 1bit / 240x128")
