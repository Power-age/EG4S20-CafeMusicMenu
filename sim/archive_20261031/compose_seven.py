"""7 页预览：每页不同画幅 + 不同版式，画在 640x480 画布上（黑边由 FPGA 等比缩放产生）。

画幅分配（演示多分辨率）：
  1 手冲      4:3   (640x480)   铺满
  2 卡布      16:9  (640x360)   上下黑边
  3 抹茶      1:1   (480x480)   左右黑边
  4 巴斯克    3:2   (640x427)   上下细边
  5 酸种      5:4   (600x480)   左右细边
  6 可颂      21:9  (640x274)   上下大黑边
  7 提拉米苏  4:5   (384x480)   左右大黑边
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = r"D:\AAA_University\Anlu\Project"
CV = os.path.join(ROOT, r"sim\diag_covers")
F_B = r"C:\Windows\Fonts\msyhbd.ttc"
F_R = r"C:\Windows\Fonts\msyh.ttc"

W, H = 640, 480
CREAM = (247, 241, 230)
BROWN = (58, 42, 30)
ORANGE = (214, 138, 60)
DARK = (32, 26, 22)

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


def photo_fit(path, w, h):
    im = Image.open(path).convert("RGB")
    s = max(w / im.width, h / im.height)
    im = im.resize((int(im.width * s + 0.5), int(im.height * s + 0.5)), Image.LANCZOS)
    x = (im.width - w) // 2
    y = (im.height - h) // 2
    return im.crop((x, y, x + w, y + h))


def canvas_with(img_w, img_h, bg=(10, 10, 10)):
    """把图片区域放在 640x480 中央，其余黑边。"""
    base = Image.new("RGB", (W, H), bg)
    ox, oy = (W - img_w) // 2, (H - img_h) // 2
    return base, ox, oy, img_w, img_h


def halftone_block(img, x0, y0, w, h, color, alpha=45, step=8):
    lay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    for yy in range(0, h, step):
        for xx in range(0, w, step):
            r = 2 if ((xx // step + yy // step) % 2 == 0) else 1
            d.ellipse([xx, yy, xx + r * 2, yy + r * 2], fill=color + (alpha,))
    img.paste(Image.alpha_composite(img.crop((x0, y0, x0 + w, y0 + h)).convert("RGBA"), lay).convert("RGB"), (x0, y0))


# ---------------------------------------------------------------- 版式 1：波普竖排 4:3
def p1():
    px_, py_, pw_, ph_ = 0, 0, 640, 480
    base, ox, oy, iw, ih = canvas_with(pw_, ph_)
    page = Image.new("RGBA", (iw, ih), CREAM + (255,))
    d = ImageDraw.Draw(page)
    halftone_block(page, 0, 0, iw, ih, ORANGE, 40)
    for i in range(4):
        d.line([(0, 16 + i * 16), (110, -50 + i * 16)], fill=ORANGE + (210,), width=9)
    cx, cy, r = 430, 205, 168
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(232, 164, 92, 255))
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=BROWN + (255,), width=6)
    pr = r - 24
    ph = photo_fit(os.path.join(CV, "card_left.png"), pr * 2, pr * 2)
    m = Image.new("L", (pr * 2, pr * 2), 0)
    ImageDraw.Draw(m).ellipse([0, 0, pr * 2 - 1, pr * 2 - 1], fill=255)
    page.paste(ph, (cx - pr, cy - pr), m)
    for i, ch in enumerate("手冲埃塞"):
        d.text((30, 24 + i * 62), ch, font=ImageFont.truetype(F_B, 58), fill=BROWN + (255,),
               stroke_width=4, stroke_fill=CREAM + (255,))
    d.rectangle([0, 392, iw, ih], fill=BROWN + (255,))
    stamp(page, [("¥28", F_B, 72, 2, 0)], 180, 82, 16, 396, CREAM)
    stamp(page, [("花香与柑橘", F_R, 17, 0, 0)], 200, 24, 250, 432, CREAM)
    base.paste(page.convert("RGB"), (ox, oy))
    return base


# ---------------------------------------------------------------- 版式 2：渐变横排 16:9
def p2():
    base, ox, oy, iw, ih = canvas_with(640, 360)
    page = Image.new("RGBA", (iw, ih), (250, 244, 234, 255))
    d = ImageDraw.Draw(page)
    for rr in range(420, 0, -8):          # 径向渐变
        t = rr / 420
        d.ellipse([320 - rr, 180 - rr * 0.7, 320 + rr, 180 + rr * 0.7],
                  fill=(int(250 - 20 * (1 - t)), int(240 - 60 * (1 - t)), int(225 - 100 * (1 - t))) + (255,))
    ph = photo_fit(os.path.join(CV, "PIC2_R.png"), 320, 360)
    page.paste(ph, (320, 0))
    d = ImageDraw.Draw(page)
    # 左侧文字
    d.text((28, 40), "CLASSIC", font=ImageFont.truetype(F_R, 18), fill=(120, 78, 40))
    d.text((28, 62), "CAPPUCCINO", font=ImageFont.truetype(F_R, 12), fill=(150, 108, 66))
    d.text((26, 96), "卡布", font=ImageFont.truetype(F_B, 64), fill=BROWN + (255,),
           stroke_width=3, stroke_fill=(255, 250, 242, 255))
    d.text((26, 168), "奇诺", font=ImageFont.truetype(F_B, 64), fill=BROWN + (255,),
           stroke_width=3, stroke_fill=(255, 250, 242, 255))
    # 价格带（左下）
    d.rounded_rectangle([24, 268, 300, 344], radius=12, fill=BROWN + (255,))
    stamp(page, [("¥26", F_B, 46, 6, 2), ("奶泡绵密", F_R, 15, 116, 34)], 270, 66, 32, 274, CREAM)
    base.paste(page.convert("RGB"), (ox, oy))
    return base


# ---------------------------------------------------------------- 版式 3：暗调居中 1:1
def p3():
    base, ox, oy, iw, ih = canvas_with(480, 480)
    page = Image.new("RGBA", (iw, ih), (26, 24, 22, 255))
    ph = photo_fit(os.path.join(CV, "PIC4_L.png"), ih, ih)
    m = Image.new("L", (ih, ih), 0)
    ImageDraw.Draw(m).ellipse([6, 6, ih - 7, ih - 7], fill=255)
    page.paste(ph, (0, 0), m)
    d = ImageDraw.Draw(page)
    d.ellipse([6, 6, ih - 7, ih - 7], outline=(214, 168, 110, 255), width=4)
    d.text((44, 300), "抹茶拿铁", font=ImageFont.truetype(F_B, 62), fill=(255, 246, 228, 255),
           stroke_width=4, stroke_fill=(20, 18, 16, 255))
    d.text((46, 372), "MATCHA LATTE", font=ImageFont.truetype(F_R, 16), fill=(226, 178, 116, 255))
    d.line([(46, 396), (200, 396)], fill=(226, 178, 116, 255), width=3)
    stamp(page, [("¥30", F_B, 46, 0, 0)], 150, 58, 46, 404, (255, 246, 228))
    stamp(page, [("宇治抹茶", F_R, 15, 0, 0)], 90, 22, 210, 418, (232, 200, 160))
    base.paste(page.convert("RGB"), (ox, oy))
    return base


# ---------------------------------------------------------------- 版式 4：杂志左图右文 3:2
def p4():
    base, ox, oy, iw, ih = canvas_with(640, 427)
    page = Image.new("RGBA", (iw, ih), CREAM + (255,))
    ph = photo_fit(os.path.join(CV, "PIC4_R.png"), 360, ih)
    page.paste(ph, (0, 0))
    d = ImageDraw.Draw(page)
    d.rectangle([352, 0, 360, ih], fill=CREAM + (255,))
    d.text((392, 54), "BASQUE", font=ImageFont.truetype(F_R, 16), fill=(150, 108, 66))
    d.text((388, 84), "巴斯克", font=ImageFont.truetype(F_B, 52), fill=BROWN + (255,))
    d.text((388, 146), "芝士", font=ImageFont.truetype(F_B, 52), fill=BROWN + (255,))
    d.line([(390, 216), (560, 216)], fill=(200, 190, 178, 255), width=2)
    stamp(page, [("¥32", F_B, 54, 0, 0), ("焦香表层 · 内心流心", F_R, 14, 0, 62)], 240, 84, 388, 236, BROWN)
    base.paste(page.convert("RGB"), (ox, oy))
    return base


# ---------------------------------------------------------------- 版式 5：几何拼贴 5:4
def p5():
    base, ox, oy, iw, ih = canvas_with(600, 480)
    page = Image.new("RGBA", (iw, ih), (238, 226, 210, 255))
    d = ImageDraw.Draw(page)
    d.rectangle([0, 0, 236, ih], fill=(214, 138, 60, 255))
    d.rectangle([0, 0, 236, 96], fill=BROWN + (255,))
    ph = photo_fit(os.path.join(CV, "PIC3_L.png"), 340, 360)
    page.paste(ph, (246, 60))
    d = ImageDraw.Draw(page)
    d.rectangle([246, 60, 585, 419], outline=CREAM + (255,), width=5)
    d.text((18, 24), "SOURDOUGH", font=ImageFont.truetype(F_R, 15), fill=CREAM + (255,))
    d.text((22, 120), "酸种", font=ImageFont.truetype(F_B, 58), fill=(255, 250, 240, 255))
    d.text((22, 186), "面包", font=ImageFont.truetype(F_B, 58), fill=(255, 250, 240, 255))
    stamp(page, [("¥22", F_B, 48, 0, 0), ("天然酵母", F_R, 15, 0, 56)], 170, 80, 26, 280, (255, 250, 240))
    stamp(page, [("慢发酵", F_R, 14, 0, 0)], 100, 20, 26, 372, (255, 236, 210))
    base.paste(page.convert("RGB"), (ox, oy))
    return base


# ---------------------------------------------------------------- 版式 6：超宽横幅 21:9
def p6():
    base, ox, oy, iw, ih = canvas_with(640, 274)
    page = Image.new("RGBA", (iw, ih), (250, 246, 238, 255))
    ph = photo_fit(os.path.join(CV, "PIC3_R.png"), 400, ih)
    page.paste(ph, (240, 0))
    d = ImageDraw.Draw(page)
    d.rectangle([0, 0, 240, ih], fill=BROWN + (255,))
    d.text((20, 26), "CROISSANT", font=ImageFont.truetype(F_R, 14), fill=(226, 178, 116, 255))
    d.text((18, 52), "黄油", font=ImageFont.truetype(F_B, 54), fill=(255, 248, 236, 255))
    d.text((18, 118), "可颂", font=ImageFont.truetype(F_B, 54), fill=(255, 248, 236, 255))
    stamp(page, [("¥18", F_B, 44, 0, 0)], 130, 58, 444, 20, BROWN)
    stamp(page, [("当日现烤 · 层次酥脆", F_R, 15, 0, 0)], 190, 22, 400, 232, BROWN)
    base.paste(page.convert("RGB"), (ox, oy))
    return base


# ---------------------------------------------------------------- 版式 7：竖长图 4:5
def p7():
    base, ox, oy, iw, ih = canvas_with(384, 480)
    page = Image.new("RGBA", (iw, ih), (244, 236, 226, 255))
    d = ImageDraw.Draw(page)
    for rr in range(300, 0, -10):
        d.ellipse([192 - rr, 200 - rr, 192 + rr, 200 + rr],
                  fill=(int(246 - 26 * (1 - rr / 300)), int(228 - 54 * (1 - rr / 300)), int(206 - 70 * (1 - rr / 300))) + (255,))
    d.text((28, 26), "TIRAMISU", font=ImageFont.truetype(F_R, 15), fill=(140, 96, 60))
    d.text((26, 54), "提拉", font=ImageFont.truetype(F_B, 52), fill=BROWN + (255,))
    d.text((26, 112), "米苏", font=ImageFont.truetype(F_B, 52), fill=BROWN + (255,))
    d.rounded_rectangle([40, 190, 344, 396], radius=100, fill=(198, 172, 140, 255))
    d.text((150, 282), "照片待补", font=ImageFont.truetype(F_B, 20), fill=(120, 96, 74, 255))
    d.rectangle([0, 410, iw, ih], fill=BROWN + (255,))
    stamp(page, [("¥30", F_B, 48, 0, 0)], 150, 62, 18, 414, CREAM)
    stamp(page, [("马斯卡彭 · 可可微苦", F_R, 13, 0, 0)], 190, 20, 168, 432, CREAM)
    base.paste(page.convert("RGB"), (ox, oy))
    return base


if __name__ == "__main__":
    funcs = [("p1", p1), ("p2", p2), ("p3", p3), ("p4", p4), ("p5", p5), ("p6", p6), ("p7", p7)]
    imgs = []
    for name, fn in funcs:
        im = fn()
        im.save(os.path.join(CV, "seven_%s.png" % name))
        imgs.append(im)
        print("生成:", name)
    cols, rows = 4, 2
    sheet = Image.new("RGB", (cols * (W + 8), rows * (H + 8)), (24, 24, 24))
    for i, im in enumerate(imgs):
        sheet.paste(im, ((i % cols) * (W + 8), (i // cols) * (H + 8)))
    sheet.save(os.path.join(CV, "seven_pages.png"))
    print("总览: seven_pages.png")
