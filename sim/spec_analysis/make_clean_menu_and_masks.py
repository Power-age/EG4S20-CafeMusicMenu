"""1) 用原始底图重出 4 张无文字菜单图（卡片文字改由 FPGA 叠加）
   2) 生成 8 块卡内文字 mask（左卡/右卡各一，240x128 / 2bit）"""
import shutil
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter, ImageDraw, ImageFont

SRC = Path(r"D:\AAA_University\Anlu\Project\doc\TF卡\bmp\好图\菜单图_v2")
OUT_IMG = Path(r"D:\AAA_University\Anlu\Project\doc\TF卡\bmp\好图\菜单图_v2\成品_clean")
OUT_MSK = Path(r"D:\AAA_University\Anlu\Project\doc\TF卡\sub_mask_v2")
FONT_R = r"C:\Windows\Fonts\msyh.ttc"
FONT_B = r"C:\Windows\Fonts\msyhbd.ttc"
W, H = 1280, 960

MW, MH = 240, 128          # 每块文字 mask 的屏幕像素尺寸

PAGES = [
    ("1.png",   [("手冲埃塞俄比亚", "柑橘与花香 口感干净", "¥28"),
                 ("经典卡布奇诺", "绵密奶泡 醇厚回甘", "¥26")]),
    ("2.png",   [("酸种面包", "天然酵母 慢发酵", "¥22"),
                 ("黄油可颂", "当日现烤 层次酥脆", "¥18")]),
    ("3.png",   [("抹茶拿铁", "宇治抹茶 微苦回甘", "¥30"),
                 ("巴斯克芝士", "焦香表层 内心流心", "¥32")]),
    ("4_v3.png", [("冰美式", "双份浓缩 清爽利落", "¥24"),
                  ("蓝莓麦芬", "果粒饱满 微甜不腻", "¥20")]),
]


def prep(im, full_h=1086):
    if im.mode != "RGBA":
        return im.convert("RGB")
    a = np.array(im)
    alpha = a[:, :, 3]
    h, w = alpha.shape
    solid = np.where(alpha.min(axis=1) >= 250)[0]
    last = int(solid.max()) if len(solid) else h - 1
    rgb = Image.fromarray(a[:, :, :3], "RGB").crop((0, 0, w, last + 1))
    need = full_h - (last + 1)
    if need <= 0:
        return rgb
    src_rows = min(need, last + 1)
    band = rgb.crop((0, last + 1 - src_rows, w, last + 1)).transpose(Image.FLIP_TOP_BOTTOM)
    band = band.resize((w, need), Image.LANCZOS).filter(ImageFilter.GaussianBlur(9.0))
    out = rgb.copy()
    out.paste(band, (0, last + 1))
    return out


def render_mask(name, desc, price):
    img = Image.new("L", (MW, MH), 0)
    d = ImageDraw.Draw(img)
    fn = ImageFont.truetype(FONT_B, 26)
    fd = ImageFont.truetype(FONT_R, 17)
    fp = ImageFont.truetype(FONT_B, 26)
    d.text((6, 6), name, fill=255, font=fn)
    d.text((MW - 6 - d.textlength(price, font=fp), 6), price, fill=255, font=fp)
    d.text((6, 42), desc, fill=255, font=fd)
    q = Image.new("L", (MW, MH), 0)
    src, dst = img.load(), q.load()
    for y in range(MH):
        for x in range(MW):
            v = src[x, y]
            dst[x, y] = 0 if v < 40 else (1 if v < 120 else (2 if v < 210 else 3))
    return q


def pack(q):
    buf = bytearray(MW // 4 * MH)
    p = q.load()
    i = 0
    for y in range(MH):
        for x in range(0, MW, 4):
            b = 0
            for k in range(4):
                b |= (p[x + k, y] & 3) << (2 * k)
            buf[i] = b
            i += 1
    return bytes(buf)


OUT_IMG.mkdir(parents=True, exist_ok=True)
OUT_MSK.mkdir(parents=True, exist_ok=True)
imgs, msks = [], []
for i, (fname, items) in enumerate(PAGES, start=1):
    img = prep(Image.open(SRC / fname)).resize((W, H), Image.LANCZOS)
    dst = OUT_IMG / ("PIC%d.bmp" % i)
    img.save(dst, format="BMP")
    imgs.append(dst)
    print("  PIC%d.bmp 无文字  %.2f MB" % (i, dst.stat().st_size / 1e6))
    for k, (n, dsc, pr) in enumerate(items):
        data = pack(render_mask(n, dsc, pr))
        m = OUT_MSK / ("TXT%d%d.BIN" % (i, k + 1))
        m.write_bytes(data)
        msks.append(m)
        print("    TXT%d%d.BIN  %d B  %s" % (i, k + 1, len(data), n))

root = Path("F:/")
if root.exists():
    for f in imgs:
        shutil.copy2(str(f), str(root / f.name))
    for f in msks:
        shutil.copy2(str(f), str(root / f.name))
    print("已写卡：4 张图 + 8 块 mask")
