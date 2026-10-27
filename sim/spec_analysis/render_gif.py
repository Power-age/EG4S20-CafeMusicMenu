"""生成动态预判 GIF：同一段音乐、四种映射并排看运动感（不动 RTL）。"""
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from sig import make_music_v2
from plan_c2 import collect, run_band, LIN15
from emph import base_c1, modulate

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


def comb_slow(F, amp, amp_tbl=(0, 7, 2, 9, 1, 6, 3, 8), period=6):
    nb = F.shape[0]
    out = np.zeros_like(F)
    b = np.arange(40)
    tbl = np.array(amp_tbl)
    for i in range(nb):
        h = F[i]
        ph = int(i / period) % 8
        out[i] = np.clip(np.where(h > 0, h + tbl[(b + ph) % 8] * amp // 8, h), 0, 63)
    return out


x = make_music_v2(12.0)
M, Mc = collect(x)
F_cur = run_band(M)
F2 = base_c1(M, Mc, gs=2)
F3 = base_c1(M, Mc, gs=3)

cases = [
    ("A  现在上板（逐频段AGC）", F_cur),
    ("B  C1 GS3 + 强调峰 amp12 wb8 慢扫 + A'", modulate(F3, "crest", 12, 8, 0.5)),
    ("C  C1 GS2 + 强调峰 amp16 wb10 慢扫 + A'", modulate(F2, "crest", 16, 10, 0.5)),
    ("D  C1 GS3 + 轮转梳齿 amp8 每6块转一格 + A'", comb_slow(F3, 8)),
]

step = 4
frames = []
for i in range(0, min(F_cur.shape[0], 320), step):
    im = Image.new("RGB", (W, H * len(cases) + 6 * (len(cases) - 1)), (12, 12, 14))
    for r, (lab, F) in enumerate(cases):
        im.paste(panel(F[i], lab), (0, r * (H + 6)))
    frames.append(im.convert("P", palette=Image.ADAPTIVE, colors=64))

out = r"D:\AAA_University\Anlu\Project\doc\频谱增强_动态对比.gif"
frames[0].save(out, save_all=True, append_images=frames[1:], duration=90, loop=0, optimize=True)
print("saved", out, "frames", len(frames), im.size)

from emph import report
for lab, F in cases:
    report(lab, F)
