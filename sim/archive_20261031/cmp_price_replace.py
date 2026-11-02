"""对比验证：以「已认可的海报」为底，只把价格就地换成 FPGA 1bit 版本。

面板：① 原图  ② 擦除价格后  ③ 叠回 FPGA 价格（同位置同大小）
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = r"D:\AAA_University\Anlu\Project"
ASSET = os.path.join(ROOT, r"doc\TF卡\bmp\好图\海报素材")
CV = os.path.join(ROOT, r"sim\diag_covers")

BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32)


def to_1bit(cov, core=0.62, gone=0.18):
    h, w = cov.shape
    thr = np.tile(BAYER4, (h // 4 + 1, w // 4 + 1))[:h, :w]
    thr = (thr + 0.5) / 16.0
    t = np.clip((cov - gone) / (core - gone), 0, 1)
    return np.where(cov >= core, 1.0, np.where(cov <= gone, 0.0, (t > thr).astype(np.float32)))


def price_mask_erase(img, box, bright_text=True, thresh=0.55):
    """在 box 内按阈值找出价格字形，用背景色填掉；返回 (新图, 字形 mask, 文字色)。"""
    a = np.asarray(img).astype(np.float32) / 255.0
    x0, y0, x1, y1 = box
    sub = a[y0:y1, x0:x1]
    lum = sub @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    mask = (lum > thresh) if bright_text else (lum < (1 - thresh))
    mask = np.asarray(Image.fromarray((mask * 255).astype(np.uint8))
                      .filter(ImageFilter.MedianFilter(3))).astype(np.float32) / 255.0
    # 膨胀 3px：把抗锯齿边缘/阴影一并擦掉，避免鬼影
    mask_d = np.asarray(Image.fromarray((mask * 255).astype(np.uint8))
                        .filter(ImageFilter.MaxFilter(7))).astype(np.float32) / 255.0
    # 背景色 = box 内非文字像素的中位色
    bg = np.median(sub[mask_d < 0.5].reshape(-1, 3), axis=0) if (mask_d < 0.5).any() else sub.reshape(-1, 3).mean(0)
    # 文字色 = 字形像素的中位色
    fg = np.median(sub[mask > 0.5].reshape(-1, 3), axis=0) if (mask > 0.5).any() else np.array([1, 1, 1])
    out = a.copy()
    m = mask_d[:, :, None]
    out[y0:y1, x0:x1] = sub * (1 - m) + bg[None, None, :] * m
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)), mask, tuple(int(c * 255) for c in fg), tuple(int(c * 255) for c in bg)


def stamp_mask(img, mask, box, color, scale=1.0):
    """把字形 mask（按 scale 缩放）贴到 box 位置，用指定颜色。"""
    h, w = mask.shape
    if scale != 1.0:
        nw, nh = max(1, int(w * scale)), max(1, int(h * scale))
        mask = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).resize((nw, nh), Image.LANCZOS)).astype(np.float32) / 255.0
    bits = to_1bit(mask)
    px = img.load()
    x0, y0 = box[0], box[1]
    hh, ww = bits.shape
    for y in range(hh):
        for x in range(ww):
            if bits[y, x] > 0.5 and 0 <= x0 + x < img.width and 0 <= y0 + y < img.height:
                px[x0 + x, y0 + y] = color


if __name__ == "__main__":
    src = Image.open(os.path.join(ASSET, "p2_shouchong.png")).convert("RGB")
    box = (30, 870, 590, 1060)          # 手冲页价格区（¥28）
    erased, mask, fg, bg = price_mask_erase(src, box, bright_text=True)
    print("文字色:", fg, " 底色:", bg, " 字形像素占比: %.3f" % mask.mean())

    erased.save(os.path.join(CV, "cmp2_erased.png"))
    fpga = erased.copy()
    stamp_mask(fpga, mask, box, fg)      # 同位置同大小重画（模拟 FPGA）
    fpga.save(os.path.join(CV, "cmp2_fpga.png"))

    # 三联对比
    w, h = src.size
    sheet = Image.new("RGB", (w, h * 3 + 16), (10, 10, 10))
    sheet.paste(src, (0, 0))
    sheet.paste(erased, (0, h + 8))
    sheet.paste(fpga, (0, 2 * h + 16))
    sz = (w // 2, (h * 3 + 16) // 2)
    sheet.resize(sz, Image.LANCZOS).save(os.path.join(CV, "cmp2_sheet.png"))
    print("对比图: cmp2_sheet.png（上=原图 中=擦除后 下=FPGA重画）")
