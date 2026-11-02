"""批量：擦除 7 页海报中的价格 → 输出无价版，便于检查误伤。

bbox 需覆盖全部价格字形；底色/字色自动采样。
"""
import os
import numpy as np
from PIL import Image, ImageFilter

ROOT = r"D:\AAA_University\Anlu\Project"
ASSET = os.path.join(ROOT, r"doc\TF卡\bmp\好图\海报素材")
OUT = os.path.join(ROOT, r"sim\diag_covers\noprice")
os.makedirs(OUT, exist_ok=True)

# (文件名, 价格 bbox, 亮字压暗底=True/暗字压亮底=False)
PAGES = [
    ("p2_shouchong.png", (24, 862, 596, 1068), True),
    ("p3_cappuccino.png", (140, 630, 720, 890), True),
    ("p4_matcha.png", (380, 1140, 760, 1265), True),
    ("p5_basque.png", (1050, 530, 1465, 770), False),
    ("p6_sourdough.png", (40, 890, 570, 1060), False),
    ("p7_croissant.png", (1560, 590, 1890, 780), False),
    ("p8_tiramisu.png", (40, 1170, 500, 1345), False),
]


def erase(img, box, bright_text, thresh=0.55, grow=3):
    a = np.asarray(img).astype(np.float32) / 255.0
    x0, y0, x1, y1 = box
    sub = a[y0:y1, x0:x1]
    lum = sub @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    mask = (lum > thresh) if bright_text else (lum < (1 - thresh))
    m = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MedianFilter(3))
    if grow:
        m = m.filter(ImageFilter.MaxFilter(grow * 2 + 1))
    mask = np.asarray(m).astype(np.float32) / 255.0
    bg = np.median(sub[mask < 0.5].reshape(-1, 3), axis=0) if (mask < 0.5).any() else sub.reshape(-1, 3).mean(0)
    out = a.copy()
    mm = mask[:, :, None]
    out[y0:y1, x0:x1] = sub * (1 - mm) + bg[None, None, :] * mm
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)), mask, bg


if __name__ == "__main__":
    for name, box, bright in PAGES:
        im = Image.open(os.path.join(ASSET, name)).convert("RGB")
        out, mask, bg = erase(im, box, bright)
        p = os.path.join(OUT, name)
        out.save(p)
        print("%-20s 擦除像素占比 %.3f 底色 %s -> %s" % (name, mask.mean(), tuple(int(c * 255) for c in bg), p))

    # 拼接检查图（各页底部区域）
    tiles = []
    for name, box, _ in PAGES:
        im = Image.open(os.path.join(OUT, name))
        w, h = im.size
        t = im.crop((0, int(h * 0.55), w, h))
        sw = 640
        t = t.resize((sw, max(1, int(t.height * sw / t.width))), Image.LANCZOS)
        tiles.append(t)
    maxh = max(t.height for t in tiles)
    sheet = Image.new("RGB", (sum(t.width for t in tiles) + 6 * len(tiles), maxh), (15, 15, 15))
    x = 0
    for t in tiles:
        sheet.paste(t, (x, 0))
        x += t.width + 6
    sheet.save(os.path.join(ROOT, r"sim\diag_covers\check_noprice.png"))
    print("检查图: check_noprice.png")
