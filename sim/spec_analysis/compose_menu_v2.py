"""菜单图 v2 后期：排中文 -> 横向预压缩 1/1.28 -> 两侧用背景纹理延展填空 -> 1280x960 BMP。"""
import shutil
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SRC = Path(r"D:\AAA_University\Anlu\Project\doc\TF卡\bmp\好图\菜单图_v2")
OUT = Path(r"D:\AAA_University\Anlu\Project\doc\TF卡\bmp\好图\菜单图_v2\成品")
FONT_R = r"C:\Windows\Fonts\msyh.ttc"
FONT_B = r"C:\Windows\Fonts\msyhbd.ttc"

W, H = 1280, 960
SQUEEZE = 1.28
CW = int(W / SQUEEZE)            # 1000 内容宽
PAD = (W - CW) // 2              # 每侧 140

# 卡片文字区（相对 1448x1086 原图）
TEXT_X = [(0.078, 0.452), (0.540, 0.914)]
TEXT_Y0 = 0.690
NAME_C = (56, 40, 30)
DESC_C = (126, 108, 96)
PRICE_C = (152, 98, 56)

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


def typeset(img, items):
    w, h = img.size
    d = ImageDraw.Draw(img)
    fn = ImageFont.truetype(FONT_B, int(0.032 * w))
    fd = ImageFont.truetype(FONT_R, int(0.021 * w))
    fp = ImageFont.truetype(FONT_B, int(0.032 * w))
    for k, (name, desc, price) in enumerate(items):
        x0 = int(TEXT_X[k][0] * w)
        x1 = int(TEXT_X[k][1] * w)
        y = int(TEXT_Y0 * h)
        d.text((x0, y), name, fill=NAME_C, font=fn)
        px = x1 - d.textlength(price, font=fp)
        d.text((px, y + 2), price, fill=PRICE_C, font=fp)
        d.text((x0, y + int(0.032 * w) + 14), desc, fill=DESC_C, font=fd)
    return img


def edge_pad(img, target_w):
    """两侧用边缘像素横向拉伸填充，模拟背景延续。"""
    w, h = img.size
    need = target_w - w
    if need <= 0:
        return img
    half = need // 2
    left = img.crop((0, 0, 6, h)).resize((half, h), Image.BILINEAR).filter(ImageFilter.GaussianBlur(1.5))
    right = img.crop((w - 6, 0, w, h)).resize((need - half, h), Image.BILINEAR).filter(ImageFilter.GaussianBlur(1.5))
    out = Image.new("RGB", (target_w, h))
    out.paste(left, (0, 0))
    out.paste(img, (half, 0))
    out.paste(right, (half + w, 0))
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    outs = []
    for i, (fname, items) in enumerate(sorted(PAGES.items()), start=1):
        src = Image.open(SRC / fname).convert("RGB")
        page = typeset(src, items).resize((W, H), Image.LANCZOS)
        squeezed = page.resize((CW, H), Image.LANCZOS)
        final = edge_pad(squeezed, W)
        dst = OUT / ("PIC%d.bmp" % i)
        final.save(dst, format="BMP")
        outs.append(dst)
        print("  PIC%d.bmp  %.2f MB  %s / %s" % (i, dst.stat().st_size / 1e6, items[0][0], items[1][0]))

    root = Path("F:/")
    if root.exists():
        for f in outs:
            shutil.copy2(str(f), str(root / f.name))
        print("已写卡 4 张")
    else:
        print("F: 不可访问，仅输出到", OUT)


if __name__ == "__main__":
    main()
