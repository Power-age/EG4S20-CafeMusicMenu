"""方案 C 的观感预判图：同一帧、同一配色，按 spectrum_render 几何绘制。"""
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from map_analyze import G, FS, N, NB, GAP
from sig import make_music_v2
from plan_c import run, LIN15

W, H, BASE_Y, BAR_W, PITCH = 640, 96, 87, 12, 16
C_FILL, C_CAP, C_BASE, BG = (0xE8, 0x45, 0x8F), (0xFF, 0xE8, 0xF5), (0xFF, 0xB3, 0xD9), (32, 33, 38)


def font(sz):
    for p in [r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\arial.ttf"]:
        try:
            return ImageFont.truetype(p, sz)
        except Exception:
            pass
    return ImageFont.load_default()


def panel(heights, label):
    im = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(im)
    for b, h in enumerate(heights):
        if h <= 0:
            continue
        x0, top = b * PITCH, BASE_Y - int(h)
        d.rectangle([x0, top, x0 + BAR_W - 1, BASE_Y - 1], fill=C_FILL)
        d.rectangle([x0, top, x0 + BAR_W - 1, top + 1], fill=C_CAP)
    d.line([0, BASE_Y, W - 1, BASE_Y], fill=C_BASE)
    d.text((6, 4), label, font=font(13), fill=(235, 235, 240))
    return im


x = make_music_v2(12.0)
cases = [
    ("A  当前上板版（build①：平滑+静音门）", dict(mode="band")),
    ("B  build① + 指数提升A'（原步骤2）", dict(mode="band", gamma=LIN15)),
    ("C  方案C1 s6o48 + A'", dict(mode="glob", gslope=6, goff=48, gamma=LIN15)),
    ("D  方案C1 s7o50 + A'（更夸张）", dict(mode="glob", gslope=7, goff=50, gamma=LIN15)),
]
F = {}
for lab, kw in cases:
    F[lab] = run(x, smooth=True, **kw)
eng = F[cases[0][0]].sum(1)
k = int(np.argmin(np.abs(eng - np.percentile(eng, 72))))

gap = 6
im = Image.new("RGB", (W, H * len(cases) + gap * (len(cases) - 1)), (12, 12, 14))
for i, (lab, _) in enumerate(cases):
    im.paste(panel(F[lab][k], lab), (0, i * (H + gap)))
out = r"D:\AAA_University\Anlu\Project\doc\频谱映射_方案C对比.png"
im.save(out)
print("saved", out, im.size, "frame", k)
for lab, _ in cases:
    v = F[lab][k]
    print(f"{lab:<34} min={v.min():2d} max={v.max():2d}  " + " ".join(f"{t:2d}" for t in v[:20]))
