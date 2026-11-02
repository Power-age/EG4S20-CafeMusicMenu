"""把 2_海报工程\有字版 的 8 张海报转成交付用 BMP（24bit、按目标尺寸缩放）。"""
import os
from PIL import Image

ROOT = r"D:\AAA_University\Anlu\Project\doc\TF卡"
SRC = os.path.join(ROOT, r"2_海报工程\有字版")
DST = os.path.join(ROOT, "1_交付_写卡用")

# 页号 -> (源文件, 目标尺寸)
JOBS = [
    (1, "cover.png", (1280, 960)),
    (2, "p2_shouchong.png", (1280, 960)),
    (3, "p3_cappuccino.png", (1280, 720)),
    (4, "p4_matcha.png", (1024, 1024)),
    (5, "p5_basque.png", (1200, 800)),
    (6, "p6_sourdough.png", (1000, 800)),
    (7, "p7_croissant.png", (1680, 720)),
    (8, "p8_tiramisu.png", (1024, 1280)),
]

# 先清掉旧的 PNG 副本
for f in os.listdir(DST):
    if f.lower().endswith(".png"):
        os.remove(os.path.join(DST, f))

for idx, name, size in JOBS:
    im = Image.open(os.path.join(SRC, name)).convert("RGB")
    if im.size != size:
        im = im.resize(size, Image.LANCZOS)
    out = os.path.join(DST, "PIC%d.BMP" % idx)
    im.save(out, format="BMP")
    print("PIC%d.BMP  %s  %.2f MB" % (idx, im.size, os.path.getsize(out) / 1048576))

print("--- 交付目录 ---")
for f in sorted(os.listdir(DST)):
    p = os.path.join(DST, f)
    print("  %-16s %.2f MB" % (f, os.path.getsize(p) / 1048576))
print("合计 %.2f MB" % (sum(os.path.getsize(os.path.join(DST, f)) for f in os.listdir(DST)) / 1048576))
