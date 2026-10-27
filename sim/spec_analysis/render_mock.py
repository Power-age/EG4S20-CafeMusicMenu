"""把候选映射的条高画成接近 spectrum_render 的观感图，供上板前预判（生成 png，不改 RTL）。"""
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from map_analyze import make_music, G, FS, N, NB, GAP
from map_variants import run

W, H = 640, 96
BASE_Y = 87
BAR_W, PITCH = 12, 16
C_FILL, C_CAP, C_BASE = (0xE8, 0x45, 0x8F), (0xFF, 0xE8, 0xF5), (0xFF, 0xB3, 0xD9)
BG = (32, 33, 38)


def font(size):
    for p in [r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf", r"C:\Windows\Fonts\arial.ttf"]:
        try:
            return ImageFont.truetype(p, size)
        except Exception:
            pass
    return ImageFont.load_default()


def draw_panel(heights, label):
    im = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(im)
    for b, h in enumerate(heights):
        if h <= 0:
            continue
        x0 = b * PITCH
        top = BASE_Y - int(h)
        d.rectangle([x0, top, x0 + BAR_W - 1, BASE_Y - 1], fill=C_FILL)
        d.rectangle([x0, top, x0 + BAR_W - 1, top + 1], fill=C_CAP)
    d.line([0, BASE_Y, W - 1, BASE_Y], fill=C_BASE)
    d.text((6, 4), label, font=font(13), fill=(235, 235, 240))
    return im


x = make_music()
peak = lambda F: float(F.max())
idx_by_var = {}
for tag, kw in [("v0", dict()), ("v1", dict(smooth=True)),
                ("v2", dict(smooth=True, gamma=G["A 用户 h+(h(h-32))>>6"])),
                ("gb", dict(mode="glob", gslope=6, goff=48, smooth=True,
                            gamma=G["A 用户 h+(h(h-32))>>6"]))]:
    F = run(x, **kw)
    eng = F.sum(1)
    idx_by_var[tag] = (F, int(np.argmin(np.abs(eng - np.percentile(eng, 70)))))

k = idx_by_var["v0"][1]
rows = []
for tag, lab in [("v0", "A  当前实现 (逐频段AGC, 无平滑无gamma)"),
                 ("v1", "B  已确认方向步骤1：邻频3点平滑"),
                 ("v2", "C  已确认方向步骤1+2：平滑 + 指数提升A"),
                 ("gb", "D  方案C：全局参考AGC + 平滑 + 指数提升A")]:
    F = idx_by_var[tag][0]
    rows.append(draw_panel(F[k], lab))
rows.append(draw_panel(idx_by_var["v0"][0][0], "E  当前实现在静音(音量0)时的静止高度 26px  ← 缺陷"))
gap = 6
im = Image.new("RGB", (W, H * len(rows) + gap * (len(rows) - 1)), (12, 12, 14))
for i, r in enumerate(rows):
    im.paste(r, (0, i * (H + gap)))
out = r"D:\AAA_University\Anlu\Project\doc\频谱映射_观感对比.png"
im.save(out)
print("saved", out, im.size, "frame", k)
for tag in idx_by_var:
    print(tag, "heights:", np.round(idx_by_var[tag][0][k], 0).astype(int).tolist())
