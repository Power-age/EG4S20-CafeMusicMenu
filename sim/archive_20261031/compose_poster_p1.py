"""明亮杂志风：第一页样张（手冲埃塞俄比亚）。

产出：
  poster_p1_1280x960.BMP  —— 海报本体（含烤字，不含 FPGA 叠字）
  preview_p1_640x480.png  —— 640x480 模拟最终观感（含 FPGA 文字带，边缘抖动抗锯齿）
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = r"D:\AAA_University\Anlu\Project"
PHOTO = os.path.join(ROOT, r"sim\diag_covers\card_left.png")
OUT_BMP = os.path.join(ROOT, r"doc\TF卡\bmp\好图\八页测试\poster_p1.BMP")
OUT_PNG = os.path.join(ROOT, r"sim\diag_covers\preview_p1_640.png")

F_BOLD = r"C:\Windows\Fonts\msyhbd.ttc"
F_REG = r"C:\Windows\Fonts\msyh.ttc"

W, H = 1280, 960           # 4:3，铺满 640x480

CREAM = (246, 240, 231)
INK = (46, 38, 33)
ACCENT = (150, 108, 66)

BAYER4 = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def text_mask(items, w, h):
    """按目标分辨率渲染 1bit 文字（边缘抖动抗锯齿），返回 bits 列表。"""
    ss = 4
    big = Image.new("L", (w * ss, h * ss), 0)
    d = ImageDraw.Draw(big)
    for s, fpath, size, x, y in items:
        d.text((x * ss, y * ss), s, font=ImageFont.truetype(fpath, size * ss), fill=255)
    cov = big.resize((w, h), Image.BOX).load()
    CORE, GONE = 0.62, 0.18
    bits = [0] * (w * h)
    for y in range(h):
        for x in range(w):
            c = cov[x, y] / 255.0
            if c <= GONE:
                continue
            if c >= CORE:
                bits[y * w + x] = 1
            else:
                t = (c - GONE) / (CORE - GONE)
                thr = (BAYER4[y % 4][x % 4] + 0.5) / 16.0
                bits[y * w + x] = 1 if t > thr else 0
    # 去孤立点
    out = bits[:]
    for y in range(h):
        for x in range(w):
            if not out[y * w + x]:
                continue
            n = sum(1 for dy in (-1, 0, 1) for dx in (-1, 0, 1)
                    if not (dx == 0 and dy == 0)
                    and 0 <= y + dy < h and 0 <= x + dx < w and bits[(y + dy) * w + (x + dx)])
            if n == 0:
                out[y * w + x] = 0
    return out


def stamp(img, bits, w, h, x0, y0, color):
    px = img.load()
    for y in range(h):
        for x in range(w):
            if bits[y * w + x]:
                px[x0 + x, y0 + y] = color


# ---------------- 海报本体 ----------------
img = Image.new("RGB", (W, H), CREAM)
d = ImageDraw.Draw(img)

# 照片：右侧满幅，左侧留白做文字版面
photo = Image.open(PHOTO).convert("RGB")
pw = 720                                   # 照片宽
photo = photo.resize((pw, H), Image.LANCZOS)
img.paste(photo, (W - pw, 0))

# 左边缘柔和过渡（照片与米白底的接缝）
fade = Image.new("L", (120, H), 0)
fd = ImageDraw.Draw(fade)
for x in range(120):
    fd.line([(x, 0), (x, H)], fill=int(255 * (x / 119)))
img.paste(Image.new("RGB", (120, H), CREAM), (W - pw, 0), fade)

# 烤字：竖排小标签 + 大字商品名 + 英文
d.rectangle([70, 90, 78, 330], fill=ACCENT)          # 装饰竖线
d.text((100, 86), "SINGLE ORIGIN", font=ImageFont.truetype(F_REG, 26), fill=ACCENT)
d.text((100, 130), "手 冲", font=ImageFont.truetype(F_REG, 30), fill=ACCENT)

name_lines = ["手冲", "埃塞俄比亚"]
f_name = ImageFont.truetype(F_BOLD, 92)
for i, line in enumerate(name_lines):
    d.text((100, 210 + i * 108), line, font=f_name, fill=INK)

d.text((104, 452), "POUR-OVER  ·  ETHIOPIA", font=ImageFont.truetype(F_REG, 26), fill=(120, 108, 98))
d.line([(104, 492), (330, 492)], fill=(200, 190, 178), width=2)

img.save(OUT_BMP)
print("海报:", OUT_BMP, img.size)

# ---------------- 640x480 最终观感模拟 ----------------
prev = img.resize((640, 480), Image.LANCZOS).convert("RGB")
# FPGA 文字带：底部左侧，价格 + 副标题（与掩膜实际渲染一致）
band = text_mask([
    ("¥28", F_BOLD, 46, 4, 0),
    ("花香与柑橘 · 口感干净", F_REG, 15, 6, 58),
], 224, 84)
stamp(prev, band, 224, 84, 44, 372, (46, 38, 33))
prev.save(OUT_PNG)
print("预览:", OUT_PNG, prev.size)
