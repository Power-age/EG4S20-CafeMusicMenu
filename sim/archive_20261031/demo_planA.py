"""方案 A 演示：有字版海报完全不动，只叠加「中文角标 + 频谱条」。"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = r"D:\AAA_University\Anlu\Project"
ASSET = os.path.join(ROOT, r"doc\TF卡\2_海报工程\有字版")
CV = os.path.join(ROOT, r"sim\diag_covers")
F_B = r"C:\Windows\Fonts\msyhbd.ttc"

BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32)


def to_1bit(cov, core=0.62, gone=0.18):
    h, w = cov.shape
    thr = np.tile(BAYER4, (h // 4 + 1, w // 4 + 1))[:h, :w]
    thr = (thr + 0.5) / 16.0
    t = np.clip((cov - gone) / (core - gone), 0, 1)
    return np.where(cov >= core, 1.0, np.where(cov <= gone, 0.0, (t > thr).astype(np.float32)))


def mask_text(img, text, size, pos, color):
    f = ImageFont.truetype(F_B, size)
    ss = 4
    w = int(ImageDraw.Draw(Image.new("L", (4, 4))).textlength(text, font=f)) + 10
    h = int(size * 1.6)
    big = Image.new("L", (w * ss, h * ss), 0)
    ImageDraw.Draw(big).text((3 * ss, 3 * ss), text, font=ImageFont.truetype(F_B, size * ss), fill=255)
    cov = np.asarray(big.resize((w, h), Image.BOX)).astype(np.float32) / 255.0
    bits = to_1bit(cov)
    px = img.load()
    for y in range(h):
        for x in range(w):
            if bits[y, x] > 0.5:
                xx, yy = pos[0] + x, pos[1] + y
                if 0 <= xx < img.width and 0 <= yy < img.height:
                    px[xx, yy] = color


def spectrum(img, x0, y0, w, h, color):
    """模拟 40 段频谱条（静态示意）。"""
    rng = np.random.default_rng(7)
    seg = w / 40.0
    d = ImageDraw.Draw(img)
    for i in range(40):
        v = 0.35 + 0.6 * abs(np.sin(i * 0.7 + 1.3)) * (0.6 + 0.4 * rng.random())
        bh = max(1, int(h * v))
        x = int(x0 + i * seg)
        d.rectangle([x, y0 + h - bh, x + int(seg * 0.62), y0 + h], fill=color)


def build(name, out, badge_text, badge_pos, text_color, badge_bg, spec_color):
    im = Image.open(os.path.join(ASSET, name)).convert("RGB")
    W, H = im.size
    im = im.resize((640, int(H * 640 / W)), Image.LANCZOS) if H * 640 / W <= 480 else im.resize((int(W * 480 / H), 480), Image.LANCZOS)
    canvas = Image.new("RGB", (640, 480), (8, 8, 8))
    canvas.paste(im, ((640 - im.width) // 2, (480 - im.height) // 2))
    d = ImageDraw.Draw(canvas)
    x, y, w, h = badge_pos
    d.rounded_rectangle([x, y, x + w, y + h], radius=10, fill=badge_bg)
    mask_text(canvas, badge_text, 22, (x + 12, y + 8), text_color)
    spectrum(canvas, 0, 464, 640, 16, spec_color)
    canvas.save(os.path.join(CV, out))
    return canvas


if __name__ == "__main__":
    a = build("p2_shouchong.png", "planA_p2.png", "今日推荐", (24, 24, 150, 52),
              (246, 236, 214), (58, 42, 30), (214, 138, 60))
    b = build("p3_cappuccino.png", "planA_p3.png", "经典之选", (24, 368, 150, 52),
              (246, 236, 214), (58, 42, 30), (214, 138, 60))
    sheet = Image.new("RGB", (648 * 2, 480), (18, 18, 18))
    sheet.paste(a, (0, 0))
    sheet.paste(b, (648, 0))
    sheet.save(os.path.join(CV, "planA_demo.png"))
    print("方案 A 演示:", os.path.join(CV, "planA_demo.png"))
