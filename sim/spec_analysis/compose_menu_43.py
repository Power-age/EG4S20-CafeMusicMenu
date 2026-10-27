"""按 1024x600 显示器定制菜单图：4:3 画布 + 内容横向预压缩 1/1.28。

原理：显示器把 640x480 拉到 1024x600（横 x1.6、纵 x1.25，横向多 1.28 倍），
     所以内容必须在 1280 宽的画布里只占 1000 宽（=1280/1.28），两侧留底色，
     显示器拉伸后内容比例才是自然的，同时画框被底色填满、没有黑边。
"""
import shutil
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

SRC = Path(r"D:\AAA_University\Anlu\Project\doc\TF卡\bmp\好图\菜单图")
OUT = Path(r"D:\AAA_University\Anlu\Project\doc\TF卡\bmp\好图\菜单图\成品43")
FONT_R = r"C:\Windows\Fonts\msyh.ttc"
FONT_B = r"C:\Windows\Fonts\msyhbd.ttc"

W, H = 1280, 960
SQUEEZE = 1.28
CONTENT_W = int(W / SQUEEZE)          # 1000
X0 = (W - CONTENT_W) // 2             # 140

BG_TOP, BG_BOT = (222, 214, 201), (205, 196, 181)
CARD_FILL = (250, 246, 238)
CARD_EDGE = (203, 190, 174)
NAME_C = (56, 40, 30)
DESC_C = (124, 106, 94)
PRICE_C = (150, 96, 54)

PHOTO_X = [(0.100, 0.468), (0.524, 0.892)]
PHOTO_Y = (0.092, 0.668)

PAGES = {
    "1.png": [("手冲埃塞俄比亚", "柑橘与花香 口感干净", "¥28"),
              ("经典卡布奇诺", "绵密奶泡 醇厚回甘", "¥26")],
    "2.png": [("酸种面包", "天然酵母 慢发酵", "¥22"),
              ("黄油可颂", "当日现烤 层次酥脆", "¥18")],
    "3.png": [("抹茶拿铁", "宇治抹茶 微苦回甘", "¥30"),
              ("巴斯克芝士", "焦香表层 内心流心", "¥32")],
    "4.png": [("冰美式", "双份浓缩 清爽利落", "¥24"),
              ("蓝莓麦芬", "果粒饱满 微甜不腻", "¥20")],
}


def gradient_bg():
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / (H - 1)
        c = tuple(int(BG_TOP[i] + (BG_BOT[i] - BG_TOP[i]) * t) for i in range(3))
        d.line([(0, y), (W, y)], fill=c)
    return img


def crop_photo(img, i):
    sw, sh = img.size
    x0, x1 = PHOTO_X[i]
    return img.crop((int(x0 * sw), int(PHOTO_Y[0] * sh),
                     int(x1 * sw), int(PHOTO_Y[1] * sh)))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    outs = []
    gap = 40
    cw = (CONTENT_W - 3 * gap) // 2        # 440
    ph_h = int(cw * 0.96)                  # 422
    text_h = 170
    card_h = 24 + ph_h + text_h
    cy0 = (H - card_h) // 2

    for i, (fname, items) in enumerate(sorted(PAGES.items()), start=1):
        src = Image.open(SRC / fname).convert("RGB")
        canvas = gradient_bg()
        d = ImageDraw.Draw(canvas)

        for k in range(2):
            cx0 = X0 + gap + k * (cw + gap)
            cx1 = cx0 + cw
            cy1 = cy0 + card_h
            d.rounded_rectangle([cx0, cy0, cx1, cy1], radius=20,
                                fill=CARD_FILL, outline=CARD_EDGE, width=3)
            ph = crop_photo(src, k).resize((cw - 24, ph_h), Image.LANCZOS)
            canvas.paste(ph, (cx0 + 12, cy0 + 12))

            ty = cy0 + 12 + ph_h + 26
            name, desc, price = items[k]
            fn = ImageFont.truetype(FONT_B, 34)
            fd = ImageFont.truetype(FONT_R, 23)
            fp = ImageFont.truetype(FONT_B, 34)
            d.text((cx0 + 20, ty), name, fill=NAME_C, font=fn)
            px = cx1 - 20 - d.textlength(price, font=fp)
            d.text((px, ty), price, fill=PRICE_C, font=fp)
            d.text((cx0 + 20, ty + 50), desc, fill=DESC_C, font=fd)

        dst = OUT / ("PIC%d.bmp" % i)
        canvas.save(dst, format="BMP")
        outs.append(dst)
        print("  PIC%d.bmp  %.2f MB  %s / %s" % (i, dst.stat().st_size / 1e6, items[0][0], items[1][0]))

    root = Path("F:/")
    if root.exists():
        for f in outs:
            shutil.copy2(str(f), str(root / f.name))
        print("已写卡 4 张（4:3 + 预压缩 1.28）")


if __name__ == "__main__":
    main()
