"""按参考风格（波普撞色 + 竖排大字 + 橙色圆底 + 深棕价格带）生成 640x480 预览。

参考图要素：
  - 米白底 + 半调网点
  - 左侧竖排深棕大字标题（米白描边）+ 竖排英文
  - 右中部巨大橙色圆形衬底，圆内嵌产品照，加深棕圆环描边
  - 四角星芒、斜条纹带
  - 底部 18% 深棕带：超大价格 + 竖排虚线分隔 + 副标题
  - 右下橙色圆形徽章（HOT/NEW）
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = r"D:\AAA_University\Anlu\Project"
CV = os.path.join(ROOT, r"sim\diag_covers")

F_BOLD = r"C:\Windows\Fonts\msyhbd.ttc"
F_REG = r"C:\Windows\Fonts\msyh.ttc"

W, H = 640, 480
CREAM = (247, 241, 230)
BROWN = (58, 42, 30)
ORANGE = (214, 138, 60)
ORANGE_LT = (232, 164, 92)

BAYER4 = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def mask_bits(items, w, h):
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
    return bits


def stamp(img, items, w, h, x0, y0, color):
    bits = mask_bits(items, w, h)
    px = img.load()
    for y in range(h):
        for x in range(w):
            if bits[y * w + x] and 0 <= x0 + x < img.width and 0 <= y0 + y < img.height:
                px[x0 + x, y0 + y] = color


def halftone(img, x0, y0, w, h, color=(200, 121, 46), alpha=52, step=9):
    lay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    for yy in range(0, h, step):
        for xx in range(0, w, step):
            r = 2 if ((xx // step + yy // step) % 2 == 0) else 1
            d.ellipse([xx, yy, xx + r * 2, yy + r * 2], fill=color + (alpha,))
    img.alpha_composite(lay, (x0, y0))


def star(d, cx, cy, r, color):
    """四角星芒"""
    d.polygon([(cx, cy - r), (cx + r * 0.22, cy - r * 0.22), (cx + r, cy),
               (cx + r * 0.22, cy + r * 0.22), (cx, cy + r),
               (cx - r * 0.22, cy + r * 0.22), (cx - r, cy),
               (cx - r * 0.22, cy - r * 0.22)], fill=color)


def stripes(d, x0, y0, count, length, thick, gap, color, angle_step=1):
    for i in range(count):
        off = i * gap
        d.line([(x0 + off, y0), (x0 + off + length, y0 - length)], fill=color, width=thick)


def make_page(photo_path, title, en, price, subtitle, badge, out_name, placeholder=False):
    base = Image.new("RGBA", (W, H), CREAM + (255,))
    d = ImageDraw.Draw(base)

    # 斜条纹（右下角）
    stripes(d, 470, 470, 5, 150, 14, 24, ORANGE + (255,))
    stripes(d, 500, 470, 3, 150, 10, 24, BROWN + (255,))
    # 斜条纹（左上角）
    for i in range(4):
        d.line([(0, 20 + i * 18), (120, -40 + i * 18)], fill=ORANGE + (200,), width=10)

    halftone(base, 0, 0, W, H, alpha=44, step=9)

    # 橙色大圆 + 深棕圆环
    cx, cy, r = 434, 208, 172
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=ORANGE_LT + (255,))
    d.ellipse([cx - r + 6, cy - r + 6, cx + r - 6, cy + r - 6], fill=ORANGE + (255,))
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=BROWN + (255,), width=6)

    # 照片（圆形裁切）
    pr = r - 26
    if placeholder:
        ph = Image.new("RGB", (pr * 2, pr * 2), (226, 208, 186))
        phd = ImageDraw.Draw(ph)
        for i in range(pr * 2):
            c = int(226 - 40 * (i / (pr * 2)))
            phd.line([(0, i), (pr * 2, i)], fill=(c, c - 14, c - 34))
        phd.text((pr - 60, pr - 10), "照片待补", font=ImageFont.truetype(F_BOLD, 22), fill=(120, 96, 74))
    else:
        ph = Image.open(photo_path).convert("RGB").resize((pr * 2, pr * 2), Image.LANCZOS)
    mask = Image.new("L", (pr * 2, pr * 2), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, pr * 2 - 1, pr * 2 - 1], fill=255)
    base.paste(ph, (cx - pr, cy - pr), mask)

    # 星芒
    star(d, 292, 74, 46, BROWN + (255,))
    star(d, 596, 118, 30, BROWN + (255,))
    star(d, 344, 418, 34, BROWN + (255,))

    # 竖排大字标题（深棕 + 米白描边）
    tx, ty, tsize, step = 34, 26, 56, 60
    for i, ch in enumerate(title):
        d.text((tx, ty + i * step), ch, font=ImageFont.truetype(F_BOLD, tsize),
               fill=BROWN + (255,), stroke_width=4, stroke_fill=CREAM + (255,))

    # 竖排英文（旋转 90°）
    enimg = Image.new("RGBA", (len(en) * 22 + 20, 40), (0, 0, 0, 0))
    ImageDraw.Draw(enimg).text((2, 4), " ".join(en), font=ImageFont.truetype(F_REG, 20), fill=BROWN + (255,))
    enimg = enimg.rotate(90, expand=True)
    base.alpha_composite(enimg, (tx + tsize + 14, ty + 4))

    # 底部深棕带
    d.rectangle([0, 392, W, H], fill=BROWN + (255,))
    # 价格（掩膜层）
    stamp(base, [(price, F_BOLD, 74, 2, 0)], 190, 84, 14, 394, CREAM)
    # 竖排虚线分隔
    for yy in range(400, 474, 10):
        d.line([(232, yy), (232, yy + 5)], fill=(235, 220, 200, 200), width=2)
    # 副标题（掩膜层）
    stamp(base, [(subtitle, F_REG, 18, 0, 0)], 236, 26, 248, 430, CREAM)

    # 圆形徽章
    bx, by, br = 566, 424, 46
    d.ellipse([bx - br, by - br, bx + br, by + br], fill=ORANGE + (255,))
    d.ellipse([bx - br, by - br, bx + br, by + br], outline=CREAM + (255,), width=3)
    tw = d.textlength(badge, font=ImageFont.truetype(F_BOLD, 20))
    d.text((bx - tw / 2, by - 12), badge, font=ImageFont.truetype(F_BOLD, 20), fill=CREAM + (255,))
    star(d, bx - 26, by - 26, 9, CREAM + (255,))
    star(d, bx + 26, by - 26, 9, CREAM + (255,))

    out = os.path.join(CV, out_name)
    base.convert("RGB").save(out)
    print("生成:", out)
    return base.convert("RGB")


if __name__ == "__main__":
    pages = [
        (os.path.join(CV, "PIC3_L.png"), "酸种面包", "SOURDOUGH", "¥22", "天然酵母 · 慢发酵", "NEW", "preview_p6_sourdough.png", False),
        (os.path.join(CV, "PIC3_R.png"), "黄油可颂", "CROISSANT", "¥18", "当日现烤 · 层次酥脆", "HOT", "preview_p7_croissant.png", False),
        (None, "提拉米苏", "TIRAMISU", "¥30", "马斯卡彭 · 可可微苦", "NEW", "preview_p8_tiramisu.png", True),
    ]
    imgs = [make_page(*p) for p in pages]
    sheet = Image.new("RGB", (W * 3 + 16, H), (20, 20, 20))
    for i, im in enumerate(imgs):
        sheet.paste(im, (i * (W + 8), 0))
    sheet.save(os.path.join(CV, "preview_3more.png"))
    print("对比图: preview_3more.png")
