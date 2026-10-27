"""把商品名/短介绍/价格排进菜单图的卡片空白区，再输出 1920x1080 的 24bit BMP 并写卡。"""
import shutil
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

SRC = Path(r"D:\AAA_University\Anlu\Project\doc\TF卡\bmp\好图\菜单图")
OUT = Path(r"D:\AAA_University\Anlu\Project\doc\TF卡\bmp\好图\菜单图\成品")
FONT_R = r"C:\Windows\Fonts\msyh.ttc"
FONT_B = r"C:\Windows\Fonts\msyhbd.ttc"
TARGET = (1280, 720)

# 每页两件商品: (名称, 一句介绍, 价格)
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

# 卡片内部矩形（按图宽高的比例；四张图版式一致）
CARD_X = [(0.100, 0.470), (0.522, 0.892)]
BLANK_Y0, BLANK_Y1 = 0.690, 0.905
NAME_SZ, DESC_SZ, PRICE_SZ = 0.026, 0.019, 0.023   # 相对图宽
NAME_COLOR = (58, 42, 32)
DESC_COLOR = (122, 104, 92)
PRICE_COLOR = (150, 96, 54)


def draw_card(d, box, item, w, h):
    x0, x1 = int(box[0] * w), int(box[1] * w)
    name, desc, price = item
    fn = ImageFont.truetype(FONT_B, int(NAME_SZ * w))
    fd = ImageFont.truetype(FONT_R, int(DESC_SZ * w))
    fp = ImageFont.truetype(FONT_B, int(PRICE_SZ * w))
    # 价格右对齐，名称左对齐，同一行
    px = x1 - d.textlength(price, font=fp)
    # 文字块在空白区内垂直居中
    nsz = int(NAME_SZ * w); dsz = int(DESC_SZ * w)
    block_h = nsz + 14 + dsz
    y0 = int(BLANK_Y0 * h); y1 = int(BLANK_Y1 * h)
    y = y0 + max(0, ((y1 - y0) - block_h) // 2)
    d.text((x0, y), name, fill=NAME_COLOR, font=fn)
    d.text((px, y + (nsz - int(PRICE_SZ * w)) // 2), price, fill=PRICE_COLOR, font=fp)
    d.text((x0, y + nsz + 14), desc, fill=DESC_COLOR, font=fd)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    outs = []
    for i, (fname, items) in enumerate(sorted(PAGES.items()), start=1):
        src = SRC / fname
        im = Image.open(src).convert("RGB")
        w, h = im.size
        d = ImageDraw.Draw(im)
        for box, item in zip(CARD_X, items):
            draw_card(d, box, item, w, h)
        im = im.resize(TARGET, Image.LANCZOS)
        dst = OUT / ("PIC%d.bmp" % i)
        im.save(dst, format="BMP")
        outs.append(dst)
        print("  PIC%d.bmp <- %s  %.2f MB  %s / %s"
              % (i, fname, dst.stat().st_size / 1e6, items[0][0], items[1][0]))

    card = Path("F:/")
    if card.exists():
        for f in outs:
            shutil.copy2(str(f), str(card / f.name))
        print("已写卡 4 张")
    else:
        print("F: 不可访问，仅输出到", OUT)


if __name__ == "__main__":
    main()
