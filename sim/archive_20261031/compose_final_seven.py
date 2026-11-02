"""7 页最终预览：干净海报（按画幅等比放入 640x480）+ 烤标题 + FPGA 叠字层模拟。

标题用华文琥珀（STHUPO）/ 雅黑粗体烘焙；价格与中文行用 1bit 抖动渲染（模拟 FPGA 掩膜）。
每页的坐标按干净海报的留白区设定。
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = r"D:\AAA_University\Anlu\Project"
CV = os.path.join(ROOT, r"sim\diag_covers")
ASSET = os.path.join(ROOT, r"doc\TF卡\bmp\好图\海报素材")

F_HP = r"C:\Windows\Fonts\STHUPO.TTF"      # 华文琥珀（圆润粗体，接近海报字感）
F_B = r"C:\Windows\Fonts\msyhbd.ttc"
F_R = r"C:\Windows\Fonts\msyh.ttc"

CREAM = (246, 236, 214)
BROWN = (58, 42, 30)
WHITE = (250, 246, 238)

BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32)


def to_1bit(cov, core=0.62, gone=0.18):
    h, w = cov.shape
    thr = np.tile(BAYER4, (h // 4 + 1, w // 4 + 1))[:h, :w]
    thr = (thr + 0.5) / 16.0
    t = np.clip((cov - gone) / (core - gone), 0, 1)
    return np.where(cov >= core, 1.0, np.where(cov <= gone, 0.0, (t > thr).astype(np.float32)))


def text_1bit(text, font_path, size, color, base, pos):
    """1bit 渲染并贴到 base（模拟 FPGA 掩膜文字）。"""
    f = ImageFont.truetype(font_path, size)
    d0 = ImageDraw.Draw(Image.new("L", (4, 4)))
    w = int(d0.textlength(text, font=f)) + 8
    h = int(size * 1.5)
    ss = 4
    big = Image.new("L", (w * ss, h * ss), 0)
    ImageDraw.Draw(big).text((2 * ss, 2 * ss), text, font=ImageFont.truetype(font_path, size * ss), fill=255)
    cov = np.asarray(big.resize((w, h), Image.BOX)).astype(np.float32) / 255.0
    bits = to_1bit(cov)
    px = base.load()
    for y in range(h):
        for x in range(w):
            if bits[y, x] > 0.5:
                xx, yy = pos[0] + x, pos[1] + y
                if 0 <= xx < base.width and 0 <= yy < base.height:
                    px[xx, yy] = color


def baked_title(base, text, size, color, pos, outline=None, vert=False, gap=None):
    """烤标题（8bit 抗锯齿、可描边、可竖排）。"""
    gap = gap or int(size * 1.06)
    for i, ch in enumerate(text):
        if vert:
            p = (pos[0], pos[1] + i * gap)
        else:
            p = (pos[0] + i * gap, pos[1])
        ImageDraw.Draw(base).text(p, ch, font=ImageFont.truetype(F_HP, size), fill=color,
                                  stroke_width=3 if outline else 0, stroke_fill=outline)


def make(name, aspect, cfg):
    src = Image.open(os.path.join(ASSET, name)).convert("RGB")
    aw, ah = aspect
    sw = 640
    sh = int(round(sw * ah / aw))
    if sh > 480:
        sh = 480
        sw = int(round(sh * aw / ah))
    img = src.resize((sw, sh), Image.LANCZOS)
    base = Image.new("RGB", (640, 480), (8, 8, 8))
    ox, oy = (640 - sw) // 2, (480 - sh) // 2
    base.paste(img, (ox, oy))
    d = ImageDraw.Draw(base)

    # 烤标题
    for t in cfg.get("baked", []):
        baked_title(base, t["text"], t["size"], t["color"], (ox + t["x"], oy + t["y"]),
                    outline=t.get("outline"), vert=t.get("vert", False), gap=t.get("gap"))
    # 英文（普通字体）
    for t in cfg.get("baked_en", []):
        d.text((ox + t["x"], oy + t["y"]), t["text"], font=ImageFont.truetype(F_R, t["size"]), fill=t["color"])

    # FPGA 层：价格 + 中文行
    for t in cfg.get("fpga", []):
        text_1bit(t["text"], F_B, t["size"], t["color"], base, (ox + t["x"], oy + t["y"]))

    return base, (ox, oy, sw, sh)


CONFIG = {
    "clean_p2.png": dict(aspect=(4, 3), baked=[
        dict(text="手冲埃塞俄比亚", size=34, color=BROWN, x=18, y=40, outline=CREAM, vert=True, gap=38),
    ], baked_en=[dict(text="POUR-OVER", size=15, color=BROWN, x=66, y=44)],
        fpga=[dict(text="¥28", size=48, color=CREAM, x=24, y=400),
              dict(text="今日推荐 · 手冲埃塞俄比亚", size=20, color=CREAM, x=140, y=414)]),

    "clean_p3.png": dict(aspect=(16, 9), baked=[
        dict(text="卡布", size=54, color=BROWN, x=40, y=60, outline=CREAM),
        dict(text="奇诺", size=54, color=BROWN, x=40, y=130, outline=CREAM),
    ], baked_en=[dict(text="CLASSIC CAPPUCCINO", size=18, color=(150, 108, 66), x=42, y=30)],
        fpga=[dict(text="¥26", size=44, color=CREAM, x=56, y=300),
              dict(text="奶泡绵密 · 醇厚回甘", size=20, color=CREAM, x=190, y=312)]),

    "clean_p4.png": dict(aspect=(1, 1), baked=[
        dict(text="抹茶拿铁", size=42, color=WHITE, x=108, y=334),
    ], baked_en=[dict(text="MATCHA LATTE", size=14, color=(226, 178, 116), x=232, y=286)],
        fpga=[dict(text="¥30", size=40, color=(226, 190, 130), x=196, y=392),
              dict(text="宇治抹茶 · 微苦回甘", size=16, color=WHITE, x=290, y=400)]),

    "clean_p5.png": dict(aspect=(3, 2), baked=[
        dict(text="巴斯克", size=46, color=BROWN, x=392, y=150),
        dict(text="芝士", size=46, color=BROWN, x=392, y=210),
    ], baked_en=[dict(text="BASQUE CHEESECAKE", size=16, color=(160, 120, 80), x=392, y=112)],
        fpga=[dict(text="¥32", size=40, color=(196, 118, 50), x=392, y=280),
              dict(text="焦香表层 · 内心流心", size=16, color=(120, 90, 60), x=392, y=330)]),

    "clean_p6.png": dict(aspect=(5, 4), baked=[
        dict(text="酸种", size=48, color=WHITE, x=30, y=250),
        dict(text="面包", size=48, color=WHITE, x=30, y=310),
    ], baked_en=[dict(text="SOURDOUGH", size=17, color=WHITE, x=32, y=40)],
        fpga=[dict(text="¥22", size=48, color=BROWN, x=40, y=400),
              dict(text="天然酵母 · 慢发酵", size=22, color=BROWN, x=190, y=414)]),

    "clean_p7.png": dict(aspect=(21, 9), baked=[
        dict(text="黄油", size=44, color=WHITE, x=34, y=52),
        dict(text="可颂", size=44, color=WHITE, x=34, y=102),
    ], baked_en=[dict(text="CROISSANT", size=14, color=(226, 178, 116), x=36, y=30)],
        fpga=[dict(text="¥18", size=30, color=BROWN, x=534, y=196),
              dict(text="当日现烤 · 层次酥脆", size=14, color=BROWN, x=300, y=240)]),

    "clean_p8.png": dict(aspect=(4, 5), baked=[
        dict(text="提拉", size=46, color=BROWN, x=24, y=120, vert=True, gap=50),
        dict(text="米苏", size=46, color=BROWN, x=24, y=230, vert=True, gap=50),
    ], baked_en=[dict(text="TIRAMISU", size=15, color=(160, 110, 70), x=82, y=120)],
        fpga=[dict(text="¥30", size=36, color=BROWN, x=24, y=378),
              dict(text="马斯卡彭 · 可可微苦", size=15, color=BROWN, x=110, y=390)]),
}

if __name__ == "__main__":
    outs = []
    for name, cfg in CONFIG.items():
        im, geom = make(name, cfg["aspect"], cfg)
        p = os.path.join(CV, "final_" + name.replace("clean_", ""))
        im.save(p)
        print("生成:", os.path.basename(p), "图像区:", geom)
        outs.append(im)
    cols, rows = 4, 2
    sheet = Image.new("RGB", (cols * 648, rows * 488), (24, 24, 24))
    for i, im in enumerate(outs):
        sheet.paste(im, ((i % cols) * 648, (i // cols) * 488))
    sheet.save(os.path.join(CV, "final_seven.png"))
    print("总览: final_seven.png")
