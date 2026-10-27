"""方案 C 观感预判图（不改 RTL）：当前上板版 vs 候选参数。"""
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from sig import make_music_v2
from plan_c2 import collect, run_band, run_glob, LIN15

W, H, BASE_Y, BAR_W, PITCH = 640, 96, 87, 12, 16
C_FILL, C_CAP, C_BASE, BG = (0xE8, 0x45, 0x8F), (0xFF, 0xE8, 0xF5), (0xFF, 0xB3, 0xD9), (32, 33, 38)


def font(sz):
    for p in [r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\arial.ttf"]:
        try:
            return ImageFont.truetype(p, sz)
        except Exception:
            pass
    return ImageFont.load_default()


def panel(h, label):
    im = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(im)
    for b, v in enumerate(h):
        if v <= 0:
            continue
        x0, top = b * PITCH, BASE_Y - int(v)
        d.rectangle([x0, top, x0 + BAR_W - 1, BASE_Y - 1], fill=C_FILL)
        d.rectangle([x0, top, x0 + BAR_W - 1, top + 1], fill=C_CAP)
    d.line([0, BASE_Y, W - 1, BASE_Y], fill=C_BASE)
    d.text((6, 4), label, font=font(13), fill=(235, 235, 240))
    return im


x = make_music_v2(12.0)
M, Mc = collect(x)
cases = [
    ("A  现在上板的版本（逐频段 AGC + 平滑）", run_band(M)),
    ("B  只加指数提升 A'（原步骤2）", run_band(M, gamma=LIN15)),
    ("C  方案C1  GS=3(12px/oct) GOFF=44 + A'", run_glob(M, Mc, gs=3, goff=44, gamma=LIN15)),
    ("D  方案C1  GS=4(16px/oct) GOFF=48 + A'", run_glob(M, Mc, gs=4, goff=48, gamma=LIN15)),
]
frames = {}
for lab, F in cases:
    eng = F.sum(1)
    frames[lab] = (F, int(np.argmin(np.abs(eng - np.percentile(eng, 72)))))

gap = 6
im = Image.new("RGB", (W, H * len(cases) + gap * (len(cases) - 1)), (12, 12, 14))
for i, (lab, _) in enumerate(cases):
    F, k = frames[lab]
    im.paste(panel(F[k], lab), (0, i * (H + gap)))
out = r"D:\AAA_University\Anlu\Project\doc\频谱映射_方案C对比.png"
im.save(out)
print("saved", out, im.size)
for lab, _ in cases:
    F, k = frames[lab]
    v = F[k]
    print(f"{lab:<42} 帧{k:>3} min={v.min():2d} max={v.max():2d} | " + " ".join(f"{t:2d}" for t in v))
