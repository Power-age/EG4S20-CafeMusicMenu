"""把「有字版」里的文字层抠出来，按相对坐标贴到「无字版」上。

做法：
  - 每个文字区块给出 bbox（有字版坐标）；
  - 区块内按"文字主色"做颜色距离筛选，得到字形 alpha（保留原始颜色/描边/阴影）；
  - 按 bbox 的相对位置（x/W, y/H）映射到无字版，贴上去。
输出：sim/diag_covers/rebuilt/pN.png
"""
import os
import numpy as np
from PIL import Image

ROOT = r"D:\AAA_University\Anlu\Project"
A = os.path.join(ROOT, r"doc\TF卡\2_海报工程\有字版")
B = os.path.join(ROOT, r"doc\TF卡\2_海报工程\无字版")
OUT = os.path.join(ROOT, r"sim\diag_covers\rebuilt")
os.makedirs(OUT, exist_ok=True)

# 每页: (有字版文件名, 无字版文件名, [文字区块 bbox...])
PAGES = {
    2: ("p2_shouchong.png", "clean_p2.png", [
        (0, 20, 420, 840),          # 竖排标题 + POUR-OVER
        (700, 850, 1448, 1086),     # 副标题
        (20, 850, 640, 1086),       # 价格 ¥28
    ]),
    3: ("p3_cappuccino.png", "clean_p3.png", [
        (20, 20, 640, 340),         # CLASSIC CAPPUCCINO + 卡布奇诺
        (120, 600, 720, 890),       # ¥26 + 奶泡绵密
    ]),
    4: ("p4_matcha.png", "clean_p4.png", [
        (300, 770, 960, 1010),      # MATCHA LATTE + 抹茶拿铁
        (340, 1040, 1120, 1260),    # ¥30 + 宇治抹茶
    ]),
    5: ("p5_basque.png", "clean_p5.png", [
        (990, 90, 1536, 530),       # 英文 + 巴斯克芝士 + 副标题
        (1030, 540, 1470, 790),     # ¥32
    ]),
    6: ("p6_sourdough.png", "clean_p6.png", [
        (0, 80, 520, 600),          # SOURDOUGH + 酸种面包
        (0, 840, 1402, 1122),       # ¥22 + 天然酵母
    ]),
    7: ("p7_croissant.png", "clean_p7.png", [
        (0, 50, 660, 520),          # CROISSANT + 黄油可颂
        (1500, 560, 1916, 800),     # ¥18
        (560, 660, 1520, 790),      # 当日现烤
    ]),
    8: ("p8_tiramisu.png", "clean_p8.png", [
        (0, 110, 340, 720),         # 竖排标题
        (180, 130, 400, 420),       # TIRAMISU
        (0, 1100, 1122, 1402),      # ¥30 + 马斯卡彭
    ]),
}


def text_layer(img, box, tol=0.30):
    """从 img 的 box 区域抠出文字层（RGBA），保留原色。"""
    a = np.asarray(img).astype(np.float32) / 255.0
    x0, y0, x1, y1 = box
    sub = a[y0:y1, x0:x1]
    lum = sub @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    # 文字 = 与区域中位色差异大的像素
    med = np.median(sub.reshape(-1, 3), axis=0)
    dist = np.sqrt(((sub - med[None, None, :]) ** 2).sum(axis=2))
    mask = (dist > tol) & ((lum > 0.62) | (lum < 0.38))
    alpha = np.clip((dist - tol * 0.6) / (tol * 1.6), 0, 1) * mask
    rgba = np.dstack([sub, alpha])
    return Image.fromarray((rgba * 255).astype(np.uint8), "RGBA")


if __name__ == "__main__":
    for idx, (ftext, fclean, boxes) in PAGES.items():
        a = Image.open(os.path.join(A, ftext)).convert("RGB")
        b = Image.open(os.path.join(B, fclean)).convert("RGB")
        W, H = a.size
        Wb, Hb = b.size
        canvas = b.convert("RGBA")
        for box in boxes:
            layer = text_layer(a, box)
            # 相对坐标映射
            nx = int(round(box[0] / W * Wb))
            ny = int(round(box[1] / H * Hb))
            nw = int(round((box[2] - box[0]) / W * Wb))
            nh = int(round((box[3] - box[1]) / H * Hb))
            layer = layer.resize((nw, nh), Image.LANCZOS)
            canvas.alpha_composite(layer, (nx, ny))
        out = canvas.convert("RGB")
        p = os.path.join(OUT, "p%d.png" % idx)
        out.save(p)
        print("p%d -> %s  (%dx%d)" % (idx, p, *out.size))
