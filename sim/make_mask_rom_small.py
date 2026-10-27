"""1bit / 200x80 / 三行 / 8 块合一 ROM（4096 x 32bit = 16KB ≈ 14 块 EMB，符合器件余量）"""
import io
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HDL = Path(r"D:\AAA_University\Anlu\Project\src\user_source\hdl_source")
FONT_R = r"C:\Windows\Fonts\msyh.ttc"
FONT_B = r"C:\Windows\Fonts\msyhbd.ttc"

MW, MH = 200, 80
WPM = 512          # 每块占 512 字（500 有效 + 补零），8 块 = 4096

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
    fn = ImageFont.truetype(FONT_B, 26)
    fd = ImageFont.truetype(FONT_R, 19)
    fp = ImageFont.truetype(FONT_B, 22)
    d.text((3, 0), name, fill=255, font=fn)          # 名称独占第一行
    d.text((3, 30), d1, fill=255, font=fd)
    d.text((3, 53), d2, fill=255, font=fd)
    # 价格移到右下角，避免与名称重叠
    d.text((MW - 3 - d.textlength(price, font=fp), 52), price, fill=255, font=fp)
    return img


def pack(img):
    px = img.load()
    bits = []
    for y in range(MH):
        for x in range(MW):
            bits.append(1 if px[x, y] > 110 else 0)
    words = []
    for i in range(0, len(bits), 32):
        chunk = bits[i:i + 32] + [0] * (32 - len(bits[i:i + 32]))
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
        assert len(ws) <= WPM, len(ws)
        ws += [0] * (WPM - len(ws))
        all_words += ws
print("总字数:", len(all_words))
assert len(all_words) == 4096

lines = ["WIDTH=32;", "DEPTH=4096;", "", "ADDRESS_RADIX=HEX;", "DATA_RADIX=HEX;", "", "CONTENT BEGIN"]
for i, w in enumerate(all_words):
    lines.append("%04X : %08X;" % (i, w))
lines.append("END;")
io.open(HDL / "txt_all.mif", "w", encoding="ascii", newline="\n").write("\n".join(lines) + "\n")
print("已生成 txt_all.mif（1bit / 200x80 / 4096 字）")

# ---- overlay：尺寸与地址更新 ----
p = HDL / "mask_overlay.v"
s = io.open(p, encoding="utf-8").read()
s = s.replace("""    localparam [10:0] LWX0 = 11'd50,  LWX1 = 11'd290;
    localparam [10:0] RWX0 = 11'd350, RWX1 = 11'd590;
    localparam [9:0]  WY0  = 10'd335, WY1  = 10'd403;   // 240x68""",
"""    localparam [10:0] LWX0 = 11'd60,  LWX1 = 11'd260;   // 200 宽
    localparam [10:0] RWX0 = 11'd360, RWX1 = 11'd560;
    localparam [9:0]  WY0  = 10'd340, WY1  = 10'd420;   // 80 高""")
s = s.replace("(lx < 11'd240)", "(lx < 11'd200)")
s = s.replace("(rx < 11'd240)", "(rx < 11'd200)")
s = s.replace("""    wire [14:0] lin = {5'd0, ly} * 15'd240 + {4'd0, lx};   // 最大 30719，需 15 位
    wire [14:0] rin = {5'd0, ly} * 15'd240 + {4'd0, rx};
    wire [14:0] sel = in_l ? lin : rin;""",
"""    wire [13:0] lin = ly * 14'd200 + {4'd0, lx};   // 最大 15999，需 14 位
    wire [13:0] rin = ly * 14'd200 + {4'd0, rx};
    wire [13:0] sel = in_l ? lin : rin;""")
s = s.replace("""    wire [9:0]  waddr = sel[14:5];                 // 除以 32（每字 32 像素，1bit）
    wire [4:0]  bidx  = sel[4:0];
    wire [2:0]  midx  = {page, ~in_l};             // 左卡=0 右卡=1
    wire [12:0] addr  = {midx, waddr};""",
"""    wire [8:0]  waddr = sel[13:5];                 // 除以 32（每字 32 像素）
    wire [4:0]  bidx  = sel[4:0];
    wire [2:0]  midx  = {page, ~in_l};             // 左卡=0 右卡=1
    wire [11:0] addr  = {midx, waddr};             // 每块 512 字""")
s = s.replace("        .DATA_WIDTH_A(32), .ADDR_WIDTH_A(13), .DATA_DEPTH_A(8192),\n        .DATA_WIDTH_B(32), .ADDR_WIDTH_B(13), .DATA_DEPTH_B(8192),",
              "        .DATA_WIDTH_A(32), .ADDR_WIDTH_A(12), .DATA_DEPTH_A(4096),\n        .DATA_WIDTH_B(32), .ADDR_WIDTH_B(12), .DATA_DEPTH_B(4096),")
s = s.replace('reg [31:0] mem [0:8191];', 'reg [31:0] mem [0:4095];')
s = s.replace(".addrb(13'd0)", ".addrb(12'd0)")
io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("mask_overlay.v 已更新（200x80 / 4096 字）")
