"""方案 C 观感预判图（不动 RTL）：现状 / 只加 gamma / C1 推荐 / C1 激进。"""
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from sig import make_music_v2
from plan_c2 import collect, run_band, LIN15, metrics
from pk_sweep2 import run_glob_pk

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
    ("A  现在上板（逐频段AGC+平滑）", run_band(M), None),
    ("B  只加指数提升A'（原步骤2）", run_band(M, gamma=LIN15), None),
    ("C  C1推荐 GS3 GOFF48 pk2 +A'", run_glob_pk(M, Mc, gs=3, goff=48, pk=2, gamma=LIN15), None),
    ("D  C1激进 GS4 GOFF48 pk1 +A'", run_glob_pk(M, Mc, gs=4, goff=48, pk=1, gamma=LIN15), None),
]
gap = 6
im = Image.new("RGB", (W, H * len(cases) + gap * (len(cases) - 1)), (12, 12, 14))
info = []
for i, (lab, F, _) in enumerate(cases):
    eng = F.sum(1)
    k = int(np.argmin(np.abs(eng - np.percentile(eng, 72))))
    im.paste(panel(F[k], lab), (0, i * (H + gap)))
    m = metrics(F)
    info.append((lab, k, F[k], m))
out = r"D:\AAA_University\Anlu\Project\doc\频谱映射_方案C对比.png"
im.save(out)
print("saved", out, im.size)
for lab, k, v, m in info:
    print("%-34s 帧%3d 均高%5.1f 极差%5.1f p90-p10%5.1f 贴底%4.1f%% | min%2d max%2d"
          % (lab, k, m["mean"], m["span"], m["iqr"], m["zero"], v.min(), v.max()))
    print("    " + " ".join("%2d" % t for t in v))
