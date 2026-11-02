"""方案 A 单页样张：擦掉海报原价格 → 合成 FPGA 信息牌（深色圆角块 + 抠字价格 + 中文行）。

信息牌（640×480 屏幕坐标）：
  x 18..402 (384 宽)  y 376..468 (92 高)  = 35328 px … 略超预算，实际用 360×90 = 32400
  - 上排：中文一行（28px）
  - 下排：价格（46px，抠自海报）
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = r"D:\AAA_University\Anlu\Project"
CV = os.path.join(ROOT, r"sim\diag_covers")
ASSET = os.path.join(ROOT, r"doc\TF卡\bmp\好图\海报素材")
F_B = r"C:\Windows\Fonts\msyhbd.ttc"

BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32)

PRICE_BOX = (38, 852, 578, 1066)     # 海报内价格区域
BAND_RGB = (69, 48, 31)              # 深棕带底色


def erase_price(img):
    """用带底色填充价格区域（先采样四周中位色，避免色差）。"""
    a = np.asarray(img).astype(np.float32)
    x0, y0, x1, y1 = PRICE_BOX
    ring = np.concatenate([
        a[max(0, y0 - 6):y0, x0:x1].reshape(-1, 3),
        a[y1:y1 + 6, x0:x1].reshape(-1, 3),
        a[y0:y1, max(0, x0 - 6):x0].reshape(-1, 3),
        a[y0:y1, x1:x1 + 6].reshape(-1, 3),
    ])
    col = np.median(ring, axis=0)
    a[y0:y1, x0:x1] = col
    return Image.fromarray(a.astype(np.uint8)), tuple(int(c) for c in col)


def extract_glyphs(img_gray, box, target_h):
    im = img_gray.crop(box)
    a = np.asarray(im).astype(np.float32) / 255.0
    mask = (a > 0.55).astype(np.float32)
    m = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MedianFilter(3))
    mask = np.asarray(m).astype(np.float32) / 255.0
    h, w = mask.shape
    nw = max(1, int(round(w * target_h / h)))
    cov = np.asarray(Image.fromarray((mask * 255).astype(np.uint8))
                     .resize((nw, target_h), Image.LANCZOS)).astype(np.float32) / 255.0
    return cov


def to_1bit(cov, core=0.62, gone=0.18):
    h, w = cov.shape
    thr = np.tile(BAYER4, (h // 4 + 1, w // 4 + 1))[:h, :w]
    thr = (thr + 0.5) / 16.0
    t = np.clip((cov - gone) / (core - gone), 0, 1)
    return np.where(cov >= core, 1.0, np.where(cov <= gone, 0.0, (t > thr).astype(np.float32)))


def text_cov(items, w, h):
    ss = 4
    big = Image.new("L", (w * ss, h * ss), 0)
    d = ImageDraw.Draw(big)
    for s, fp, size, x, y in items:
        d.text((x * ss, y * ss), s, font=ImageFont.truetype(fp, size * ss), fill=255)
    return np.asarray(big.resize((w, h), Image.BOX)).astype(np.float32) / 255.0


def paste_bits(base, bits, x0, y0, color):
    h, w = bits.shape
    px = base.load()
    for y in range(h):
        for x in range(w):
            if bits[y, x] > 0.5 and 0 <= x0 + x < base.width and 0 <= y0 + y < base.height:
                px[x0 + x, y0 + y] = color


def build(src_name, price_label, cn_line, out_name, price_key):
    src = os.path.join(ASSET, src_name)
    img = Image.open(src).convert("RGB")
    img, col = erase_price(img)
    print("  %s 擦除用底色: %s" % (src_name, col))

    # 缩放到 4:3 屏幕内（p2 本身就是 4:3 → 640x480）
    img = img.resize((640, 480), Image.LANCZOS).convert("RGBA")

    # 信息牌底板
    plate = Image.new("RGBA", (640, 480), (0, 0, 0, 0))
    pd = ImageDraw.Draw(plate)
    pd.rounded_rectangle([18, 376, 398, 466], radius=14, fill=(58, 42, 30, 242))
    pd.rounded_rectangle([18, 376, 398, 466], radius=14, outline=(226, 178, 116, 140), width=2)
    img = Image.alpha_composite(img, plate)

    # 中文行（1bit，28px）
    cn_cov = text_cov([(cn_line, F_B, 28, 0, 0)], 356, 34)
    paste_bits(img, to_1bit(cn_cov), 34, 386, (246, 232, 206))

    # 价格：抠自海报
    price_cov = extract_glyphs(Image.open(src).convert("L"), PRICE_BOX, 52)
    pb = to_1bit(price_cov)
    paste_bits(img, pb, 34, 414, (246, 232, 206))

    img.convert("RGB").save(os.path.join(CV, out_name))
    print("  输出:", out_name)
    return img.convert("RGB")


if __name__ == "__main__":
    build("p2_shouchong.png", "¥28", "今日推荐 · 手冲埃塞俄比亚", "final_p2_mock.png", "¥28")
