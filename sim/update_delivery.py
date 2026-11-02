"""把最新海报转成交付 BMP（写入 1_交付_写卡用）。"""
import os
from PIL import Image

ROOT = r"D:\AAA_University\Anlu\Project\doc\TF卡"
SRC = os.path.join(ROOT, r"2_海报工程\有字版")
DST = os.path.join(ROOT, "1_交付_写卡用")
os.makedirs(DST, exist_ok=True)

JOBS = [
    (1, "cover_new.png",     (1280, 960)),   # 4:3
    (4, "p4_matcha_new.png", (1024, 1024)),  # 1:1
]
for idx, name, size in JOBS:
    src = os.path.join(SRC, name)
    if not os.path.exists(src):
        print("缺少", name)
        continue
    im = Image.open(src).convert("RGB")
    if im.size != size:
        im = im.resize(size, Image.LANCZOS)
    out = os.path.join(DST, "PIC%d.BMP" % idx)
    im.save(out, format="BMP")
    print("PIC%d.BMP  <- %s  %s  %.2f MB" % (idx, name, im.size, os.path.getsize(out) / 1048576))

print("--- 交付目录 ---")
for f in sorted(os.listdir(DST)):
    p = os.path.join(DST, f)
    print("  %-14s %.2f MB" % (f, os.path.getsize(p) / 1048576))
