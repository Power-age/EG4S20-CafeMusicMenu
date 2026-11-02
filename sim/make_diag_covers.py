"""生成"上采样缺陷诊断图"：不同分辨率各一张，图案里带方向性线索。

线索设计：
- 竖向绿线每 40px  → 若横向错位/丢像素，绿线会弯或断
- 横向红线每 20px  → 若丢/重复整行，红线间距会不均（数格子即可看出）
- 蓝色对角线      → 任何横向错位都会让线"锯齿化"
- 白色刻度数字    → 每 20 行标一次行号，直接读出哪一行错
"""
from PIL import Image, ImageDraw, ImageFont

FONT = r"C:\Windows\Fonts\msyhbd.ttc"
OUT = r"D:\AAA_University\Anlu\Project\sim\diag_covers"

import os
os.makedirs(OUT, exist_ok=True)


def make(w, h):
    img = Image.new("RGB", (w, h), (30, 30, 30))
    d = ImageDraw.Draw(img)
    # 竖线（每 40px，绿）
    for x in range(0, w, 40):
        d.line([(x, 0), (x, h)], fill=(0, 200, 0), width=1)
    # 横线（每 20px，红）
    for y in range(0, h, 20):
        d.line([(0, y), (w, y)], fill=(200, 0, 0), width=1)
    # 对角线（蓝）
    d.line([(0, 0), (w - 1, h - 1)], fill=(60, 120, 255), width=2)
    d.line([(w - 1, 0), (0, h - 1)], fill=(60, 120, 255), width=2)
    # 行号刻度（左侧每 20 行）
    f = ImageFont.truetype(FONT, max(10, h // 40))
    for y in range(0, h, 20):
        if (y // 20) % 2 == 0:
            d.text((3, y + 1), str(y), font=f, fill=(255, 255, 0))
    # 中心大标签
    big = ImageFont.truetype(FONT, max(16, h // 14))
    label = f"{w}x{h}"
    tw = d.textlength(label, font=big)
    d.text(((w - tw) / 2, h // 2 - h // 20), label, font=big, fill=(255, 255, 255))
    return img


for w, h in [(480, 360), (600, 450), (320, 240), (500, 375), (512, 384)]:
    im = make(w, h)
    p = os.path.join(OUT, f"diag_{w}x{h}.BMP")
    im.save(p, format="BMP")
    print("生成:", p, im.size)
