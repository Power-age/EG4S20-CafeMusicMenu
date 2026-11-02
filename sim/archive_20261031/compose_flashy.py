"""花哨商业广告风：3 套 640x480 完整成品预览（含全部文字）。

分层说明：
  - 烤字层：商品名/英文/装饰（真字体 + 描边/投影/渐变/倾斜）
  - 掩膜层：价格 + 副标题（用 make_text_mask 的边缘抖动 AA 渲染，模拟 FPGA 叠字）
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = r"D:\AAA_University\Anlu\Project"
CV = os.path.join(ROOT, r"sim\diag_covers")

F_BOLD = r"C:\Windows\Fonts\msyhbd.ttc"
F_REG = r"C:\Windows\Fonts\msyh.ttc"

W, H = 640, 480
CREAM = (246, 240, 231)
INK = (44, 34, 28)
BROWN = (58, 42, 30)
ORANGE = (200, 121, 46)
DEEP_ORANGE = (176, 92, 28)
GREEN = (86, 122, 74)

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
            if bits[y * w + x]:
                px[x0 + x, y0 + y] = color


def grad_text(size, text, font_path, px_size, top_rgb, bot_rgb, stroke=0, stroke_rgb=(255, 255, 255)):
    """渐变填充 + 可选描边的大字，返回 RGBA 图。"""
    pad = stroke + 6
    f = ImageFont.truetype(font_path, px_size)
    tmp = Image.new("L", (px_size * len(text) + pad * 2, px_size * 2 + pad * 2), 0)
    td = ImageDraw.Draw(tmp)
    td.text((pad, pad // 2), text, font=f, fill=255, stroke_width=stroke, stroke_fill=255)
    bbox = tmp.getbbox()
    tmp = tmp.crop(bbox)
    w, h = tmp.size
    grad = Image.new("RGB", (w, h))
    gd = ImageDraw.Draw(grad)
    for y in range(h):
        t = y / max(1, h - 1)
        c = tuple(int(top_rgb[i] + (bot_rgb[i] - top_rgb[i]) * t) for i in range(3))
        gd.line([(0, y), (w, y)], fill=c)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(grad, (0, 0), tmp)
    if stroke:
        # 描边：先画一圈描边色再叠渐变字
        base = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        bd = ImageDraw.Draw(base)
        bd.bitmap((0, 0), tmp, fill=stroke_rgb)
        base = base.filter(ImageFilter.MaxFilter(stroke * 2 + 1))
        base.paste(out, (0, 0), out)
        out = base
    return out


def shadowed(layer, offset=(5, 7), blur=4, alpha=120):
    a = layer.split()[3].point(lambda v: int(v * alpha / 255))
    sh = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    sh.putalpha(a)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    return sh


def rotate_paste(base, layer, angle, pos):
    r = layer.rotate(angle, expand=True, resample=Image.BICUBIC)
    sh = shadowed(r)
    base.alpha_composite(sh, (pos[0] + 6, pos[1] + 8))
    base.alpha_composite(r, pos)


def halftone(img, x0, y0, w, h, color=(255, 255, 255), alpha=46, step=8, rad=2):
    lay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    for yy in range(0, h, step):
        for xx in range(0, w, step):
            r = rad if ((xx // step + yy // step) % 2 == 0) else max(1, rad - 1)
            d.ellipse([xx, yy, xx + r * 2, yy + r * 2], fill=color + (alpha,))
    img.alpha_composite(lay, (x0, y0))


# ============================================================================
# 版式 1：撞色斜切 + 倾斜大标题 + 价格徽章
# ============================================================================
def style1():
    base = Image.new("RGBA", (W, H), CREAM + (255,))
    d = ImageDraw.Draw(base)

    # 右侧照片（整块矩形，不再斜切）
    photo = Image.open(os.path.join(CV, "card_left.png")).convert("RGB").resize((360, 440), Image.LANCZOS)
    base.paste(photo, (264, 20))
    d.rectangle([264, 20, 623, 459], outline=(255, 252, 246, 255), width=6)

    # 撞色色块
    d.polygon([(0, 0), (250, 0), (250, H), (0, H)], fill=(250, 244, 236, 255))
    d.polygon([(0, 0), (250, 0), (250, 96), (0, 150)], fill=ORANGE + (255,))
    d.polygon([(0, H), (250, H), (250, 372), (0, 424)], fill=DEEP_ORANGE + (255,))

    # 烤字
    d.text((22, 112), "SINGLE ORIGIN", font=ImageFont.truetype(F_REG, 16), fill=(120, 78, 40))
    # 竖排大字：手 冲 埃 塞 俄 比 亚（每个字单独做渐变+描边，逐字下移）
    d = ImageDraw.Draw(base)
    vy = 108
    for ch in "手冲埃塞俄比亚":
        g = grad_text(120, ch, F_BOLD, 46, (70, 44, 26), (150, 96, 48), stroke=2, stroke_rgb=(255, 250, 240))
        base.alpha_composite(g, (26, vy))
        vy += 48
    d = ImageDraw.Draw(base)
    d.text((120, 120), "SINGLE", font=ImageFont.truetype(F_REG, 15), fill=(120, 78, 40))
    d.text((120, 142), "ORIGIN", font=ImageFont.truetype(F_REG, 15), fill=(120, 78, 40))
    d.text((120, 168), "POUR-OVER", font=ImageFont.truetype(F_REG, 12), fill=(140, 100, 60))
    d.text((120, 184), "ETHIOPIA", font=ImageFont.truetype(F_REG, 12), fill=(140, 100, 60))

    # 掩膜层：价格 + 副标题（压在底部橙色块上）
    stamp(base, [("¥28", F_BOLD, 48, 6, 4)], 150, 76, 22, 380, (255, 250, 240))
    stamp(base, [("花香与柑橘 · 干净", F_REG, 15, 0, 0)], 150, 22, 26, 442, (60, 40, 26))
    return base.convert("RGB")

# 版式 2：波普圆底 + 网点 + 描边横排大字
# ============================================================================
def style2():
    base = Image.new("RGBA", (W, H), (250, 246, 238, 255))
    d = ImageDraw.Draw(base)

    # 巨大橙色圆
    d.ellipse([210, 40, 690, 520], fill=(214, 138, 60, 255))
    d.ellipse([236, 66, 664, 494], fill=(232, 164, 92, 255))

    # 照片（圆形裁切）
    photo = Image.open(os.path.join(CV, "PIC2_R.png")).convert("RGB").resize((400, 400), Image.LANCZOS)
    mask = Image.new("L", (400, 400), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, 399, 399], fill=255)
    base.paste(photo, (245, 80), mask)

    halftone(base, 0, 0, 250, H, color=(160, 96, 40), alpha=34, step=8, rad=2)
    # 斜条纹带
    for i in range(-40, 700, 28):
        d.line([(i, 470), (i + 60, 410)], fill=(240, 200, 150, 120), width=6)

    # 烤字
    t1 = grad_text(120, "卡布奇诺", F_BOLD, 56, (52, 34, 22), (120, 74, 38), stroke=4, stroke_rgb=(255, 252, 246))
    rotate_paste(base, t1, -4, (10, 40))
    d = ImageDraw.Draw(base)
    d.text((16, 108), "CLASSIC  CAPPUCCINO", font=ImageFont.truetype(F_REG, 15), fill=(120, 78, 40))
    d.rectangle([14, 20, 118, 26], fill=(58, 42, 30))

    # 掩膜层：价格 + 副标题（深色横条上）
    d.rectangle([0, 396, 640, 480], fill=(48, 36, 28, 255))
    stamp(base, [("¥26", F_BOLD, 42, 4, 2), ("奶泡绵密 · 醇厚回甘", F_REG, 17, 108, 14)], 300, 62, 22, 406, (255, 236, 210))
    # 徽章
    d.ellipse([520, 400, 630, 476], fill=(214, 138, 60, 255))
    stamp(base, [("HOT", F_BOLD, 20, 12, 8)], 52, 30, 546, 414, (60, 40, 26))
    return base.convert("RGB")


# ============================================================================
# 版式 3：渐变光效 + 弧形色带 + 大价格
# ============================================================================
def style3():
    base = Image.new("RGBA", (W, H), (252, 246, 238, 255))
    d = ImageDraw.Draw(base)
    # 径向渐变（模拟）
    for r in range(520, 0, -6):
        t = r / 520.0
        col = (int(252 - 26 * (1 - t)), int(246 - 60 * (1 - t)), int(238 - 96 * (1 - t)))
        d.ellipse([320 - r, 200 - r * 0.8, 320 + r, 200 + r * 0.8], fill=col + (255,))

    # 照片：拱形裁切
    photo = Image.open(os.path.join(CV, "PIC4_R.png")).convert("RGB").resize((360, 360), Image.LANCZOS)
    mask = Image.new("L", (360, 360), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, 359, 359], radius=120, fill=255)
    base.paste(photo, (250, 30), mask)
    # 高光弧线
    for wdt, alpha in ((5, 90), (2, 150)):
        d.arc([244, 24, 616, 396], 200, 340, fill=(255, 255, 255, alpha), width=wdt)

    # 弧形色带（价格带）
    band = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bd = ImageDraw.Draw(band)
    bd.pieslice([-160, 300, 800, 760], 190, 350, fill=(58, 42, 30, 255))
    base.alpha_composite(band)

    # 烤字
    t1 = grad_text(120, "巴斯克", F_BOLD, 54, (60, 38, 24), (140, 88, 44), stroke=3, stroke_rgb=(255, 250, 242))
    rotate_paste(base, t1, 0, (18, 52))
    d = ImageDraw.Draw(base)
    d.text((22, 120), "BASQUE  CHEESECAKE", font=ImageFont.truetype(F_REG, 14), fill=(120, 80, 44))
    d.text((22, 148), "焦香表层 · 内心流心", font=ImageFont.truetype(F_REG, 16), fill=(120, 80, 44))

    # 掩膜层：价格（弧形带上）
    stamp(base, [("¥32", F_BOLD, 52, 2, 2)], 160, 70, 40, 392, (255, 238, 212))
    stamp(base, [("今日推荐", F_REG, 16, 0, 0)], 80, 22, 208, 418, (245, 214, 176))
    return base.convert("RGB")


if __name__ == "__main__":
    imgs = [style1(), style2(), style3()]
    names = ["preview_v1_slash", "preview_v2_pop", "preview_v3_gradient"]
    for im, n in zip(imgs, names):
        p = os.path.join(CV, n + ".png")
        im.save(p)
        print("生成:", p)

    sheet = Image.new("RGB", (W * 3 + 16, H), (20, 20, 20))
    for i, im in enumerate(imgs):
        sheet.paste(im, (i * (W + 8), 0))
    sheet.save(os.path.join(CV, "preview_3styles.png"))
    print("对比图:", os.path.join(CV, "preview_3styles.png"))
