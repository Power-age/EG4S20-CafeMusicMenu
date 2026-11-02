"""验证：从 GPT 海报里抠出价格/副标题文字，转成 1bit 掩膜。

思路：文字在纯色深带上（亮字压深底）→ 亮度阈值分离 → 形态学清理 → 缩放 →
      边缘抖动量化成 1bit → 输出预览（1bit 放大 + 模拟屏幕观感）。
"""
import os
import numpy as np
from PIL import Image, ImageFilter

CV = r"D:\AAA_University\Anlu\Project\sim\diag_covers"
SRC = r"D:\AAA_University\Anlu\Project\doc\TF卡\bmp\好图\海报素材\p2_shouchong.png"

BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32)


def extract(box, thresh=140, target_h=None):
    im = Image.open(SRC).convert("L").crop(box)
    a = np.asarray(im).astype(np.float32) / 255.0
    mask = (a > thresh / 255.0).astype(np.float32)

    # 形态学：去掉细小噪点（3x3 中值 → 开运算近似）
    m = Image.fromarray((mask * 255).astype(np.uint8))
    m = m.filter(ImageFilter.MedianFilter(3))
    mask = np.asarray(m).astype(np.float32) / 255.0

    if target_h:
        h, w = mask.shape
        nw = max(1, int(round(w * target_h / h)))
        mask = np.asarray(Image.fromarray((mask * 255).astype(np.uint8))
                          .resize((nw, target_h), Image.LANCZOS)).astype(np.float32) / 255.0
    return mask


def to_1bit(cov, core=0.62, gone=0.18):
    h, w = cov.shape
    thr = np.tile(BAYER4, (h // 4 + 1, w // 4 + 1))[:h, :w]
    thr = (thr + 0.5) / 16.0
    t = np.clip((cov - gone) / (core - gone), 0, 1)
    bits = np.where(cov >= core, 1.0, np.where(cov <= gone, 0.0, (t > thr).astype(np.float32)))
    return bits


# p2 是 1448x1086，价格在左下深带上，副标题在其右侧
price_box = (38, 852, 578, 1066)
sub_box = (748, 928, 1402, 1022)

price_cov = extract(price_box, thresh=150, target_h=46)     # 目标屏幕高度 46px
sub_cov = extract(sub_box, thresh=150, target_h=18)

price_bits = to_1bit(price_cov)
sub_bits = to_1bit(sub_cov)

def bit_img(bits, fg=255, bg=0):
    return Image.fromarray((bits * 255).astype(np.uint8)).convert("L")

ph, pw = price_bits.shape
sh, sw = sub_bits.shape
print("价格掩膜:", (pw, ph), " 副标题掩膜:", (sw, sh))

# 拼一张对比图：上=原图裁切，下=1bit 掩膜
canvas_w = max(pw, sw * 2 + 20)
canvas = Image.new("L", (canvas_w, ph + sh + 60), 30)
src_crop = Image.open(SRC).convert("L").crop(price_box).resize((pw, ph), Image.LANCZOS)
canvas.paste(src_crop, (0, 0))
canvas.paste(bit_img(price_bits), (0, ph + 10))
canvas.paste(bit_img(sub_bits), (0, ph + 10 + sh + 10))
canvas = canvas.resize((canvas_w * 2, (ph + sh + 60) * 2), Image.NEAREST)
out = os.path.join(CV, "extract_test.png")
canvas.save(out)
print("对比图:", out)

# 也输出模拟屏幕观感（深棕底 + 米白字）
sim = Image.new("RGB", (pw, ph + sh + 24), (58, 42, 30))
sim.paste(Image.fromarray((price_bits * 255).astype(np.uint8)).convert("L"), (0, 0))
sim.paste(Image.fromarray((sub_bits * 255).astype(np.uint8)).convert("L"), (0, ph + 16))
sim = sim.point(lambda v: v)
sim.save(os.path.join(CV, "extract_screen_sim.png"))
print("屏幕模拟:", os.path.join(CV, "extract_screen_sim.png"))
