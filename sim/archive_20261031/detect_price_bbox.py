"""自动检测海报里"价格"字块的 bbox（无 scipy/cv2，手写连通域）。

思路：在下方 45% 区域里分别试"亮字/暗字"两种二值化，取面积最大的连通块，
并用 高宽比 / 尺寸 过滤掉背景大色块。
"""
import os
import numpy as np
from PIL import Image, ImageFilter

ASSET = r"D:\AAA_University\Anlu\Project\doc\TF卡\bmp\好图\海报素材"


def components(mask, min_area=40):
    """4 邻域连通域标记（迭代 BFS），返回 [(area, x0,y0,x1,y1)]。"""
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    out = []
    ys, xs = np.nonzero(mask)
    coords = list(zip(ys.tolist(), xs.tolist()))
    idx = 0
    for y0, x0 in coords:
        if seen[y0, x0]:
            continue
        stack = [(y0, x0)]
        seen[y0, x0] = True
        area = 0
        bx0, bx1, by0, by1 = x0, x0, y0, y0
        while stack:
            y, x = stack.pop()
            area += 1
            if x < bx0: bx0 = x
            if x > bx1: bx1 = x
            if y < by0: by0 = y
            if y > by1: by1 = y
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        if area >= min_area:
            out.append((area, bx0, by0, bx1, by1))
    return out


def detect(name, bright_text):
    p = os.path.join(ASSET, name)
    im = Image.open(p).convert("L")
    W, H = im.size
    y_start = int(H * 0.55)
    sub = im.crop((0, y_start, W, H))

    # 下采样 1/3 加速
    sc = 3
    small = sub.resize((sub.width // sc, sub.height // sc), Image.BOX)
    a = np.asarray(small).astype(np.float32) / 255.0
    mask = (a > 0.70) if bright_text else (a < 0.30)
    m = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MedianFilter(3))
    mask = np.asarray(m) > 127

    comps = components(mask, min_area=25)
    if not comps:
        return None
    comps.sort(key=lambda c: -c[0])
    best = None
    for area, x0, y0, x1, y1 in comps[:12]:
        bw, bh = x1 - x0 + 1, y1 - y0 + 1
        # 价格字形：宽度大、高度中等，排除超宽横带
        if bh < 10 or bw < 12:
            continue
        if bw / max(1, bh) > 12:      # 太扁 → 背景色带
            continue
        best = (x0 * sc, y0 * sc + y_start, x1 * sc, y1 * sc + y_start)
        break
    return best, W, H


if __name__ == "__main__":
    names = ["p2_shouchong.png", "p3_cappuccino.png", "p4_matcha.png",
             "p5_basque.png", "p6_sourdough.png", "p7_croissant.png", "p8_tiramisu.png"]
    for n in names:
        for bright in (True, False):
            r = detect(n, bright)
            if r:
                box, W, H = r
                print("%-20s bright=%-5s bbox=%s  size=%dx%d" % (n, bright, box, W, H))
