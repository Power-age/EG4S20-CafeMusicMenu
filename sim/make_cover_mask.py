"""生成封面页（page 0）的两块标题掩膜，并替换现有 txt_all.mif 的块 0/1。

几何（与 mask_overlay.v 一致）：每块 200×80 / 1bit，按 ly*200+lx 打包，500 字补零到 512。
块 0 = 左窗口：店名 + 英文；块 1 = 右窗口：slogan。
块 2~7 保持旧内容（从旧 MIF 逐块搬运）。
"""
import io
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

SRC_MIF = Path(r"D:\AAA_University\Anlu\Project\sim\backups\txt_all_before_cover.mif")
OUT_MIF = Path(r"D:\AAA_University\Anlu\Project\src\user_source\hdl_source\txt_all.mif")
PREVIEW = Path(r"D:\AAA_University\Anlu\Project\sim\cover_mask_preview.png")

W, H = 200, 80
WORDS = 512
FONT_CN = r"C:\Windows\Fonts\msyhbd.ttc"
FONT_EN = r"C:\Windows\Fonts\msyh.ttc"


def render(lines):
    """lines: [(text, font, y, color)] → 1bit 位图（PIL 'L'，0/255）"""
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)
    for text, font, y, _ in lines:
        tw = d.textlength(text, font=font)
        d.text(((W - tw) / 2, y), text, font=font, fill=255)
    return img


name_img = render([
    ("木与豆咖啡", ImageFont.truetype(FONT_CN, 38), 4, 255),
    ("WOOD & BEAN", ImageFont.truetype(FONT_EN, 13), 54, 255),
])
slogan_img = render([
    ("每日现磨", ImageFont.truetype(FONT_CN, 20), 12, 255),
    ("手冲与意式", ImageFont.truetype(FONT_CN, 20), 44, 255),
])

# 预览拼图：两张掩膜上下叠，放大 3 倍便于观察
prev = Image.new("L", (W, H * 2 + 4), 40)
prev.paste(name_img, (0, 0))
prev.paste(slogan_img, (0, H + 4))
prev.resize((W * 3, (H * 2 + 4) * 3), Image.NEAREST).save(PREVIEW)


def pack(img):
    px = img.load()
    bits = []
    for yy in range(H):
        for xx in range(W):
            bits.append(1 if px[xx, yy] >= 128 else 0)
    words = []
    for i in range(0, len(bits), 32):
        w = 0
        for j in range(32):
            if i + j < len(bits) and bits[i + j]:
                w |= 1 << j
        words.append(w)
    assert len(words) == 500, len(words)
    words += [0] * (WORDS - len(words))
    return words


def read_old():
    vals = {}
    for line in io.open(SRC_MIF, encoding="ascii"):
        line = line.strip()
        if not line or ":" not in line:
            continue
        head, tail = line.split(":", 1)
        head, tail = head.strip(), tail.strip().rstrip(";")
        if len(head) != 4:
            continue
        try:
            vals[int(head, 16)] = int(tail, 16)
        except ValueError:
            continue
    return vals


old = read_old()
assert len(old) == 4096

blocks = [pack(name_img), pack(slogan_img)]
for b in range(2, 8):
    blocks.append([old.get(b * 512 + k, 0) for k in range(512)])

words = [w for blk in blocks for w in blk]
assert len(words) == 4096

lines = ["WIDTH=32;", "DEPTH=4096;", "", "ADDRESS_RADIX=HEX;", "DATA_RADIX=HEX;", "", "CONTENT BEGIN"]
for i, w in enumerate(words):
    lines.append("%04X : %08X;" % (i, w))
lines.append("END;")
io.open(OUT_MIF, "w", encoding="ascii", newline="\n").write("\n".join(lines) + "\n")

# 自检
assert blocks[2:] == [[old.get(b * 512 + k, 0) for k in range(512)] for b in range(2, 8)]
print("块0 非零字数:", sum(1 for w in blocks[0] if w))
print("块1 非零字数:", sum(1 for w in blocks[1] if w))
print("已写入", OUT_MIF, "| 预览", PREVIEW)
