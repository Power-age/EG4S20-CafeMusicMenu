"""把 mask MIF 的指定块渲染成 PNG，检查源数据是否本身有斑点。

块结构：8192 字 × 32bit = 16 块 × 512 字；块号 = {page[2:0], card}。
块内：ly*200+lx 位序，200 宽 × 80 高。
8 个分片 MIF：slice = (block*512) / 2048，half = (word & 1) ? hi : lo
"""
import io
import os
from PIL import Image

OUTDIR = r"D:\AAA_University\Anlu\Project\src\user_source\hdl_source"
PREVIEW = r"D:\AAA_University\Anlu\Project\sim\diag_covers\mask_blocks.png"

W, H = 200, 80
WORDS = 8192

# 组装 8192 个 32 位字
words = [0] * WORDS
for slc in range(4):
    for half, shift in (("lo", 0), ("hi", 16)):
        p = os.path.join(OUTDIR, "mask_s%d_%s.mif" % (slc, half))
        for line in io.open(p, encoding="ascii"):
            line = line.strip()
            if not line or ":" not in line:
                continue
            h, t = line.split(":", 1)
            h = h.strip(); t = t.strip().rstrip(";")
            if len(h) != 3:
                continue
            try:
                idx = int(h, 16); val = int(t, 16)
            except ValueError:
                continue
            words[slc * 2048 + idx] |= (val & 0xFFFF) << shift

# 渲染 16 个块，4 列 × 4 行
sheet = Image.new("L", (W * 4, H * 4), 0)
stats = []
for blk in range(16):
    img = Image.new("L", (W, H), 0)
    px = img.load()
    nbits = 0
    for ly in range(H):
        for lx in range(W):
            bit_i = ly * W + lx
            w = words[blk * 512 + (bit_i >> 5)]
            if (w >> (bit_i & 31)) & 1:
                px[lx, ly] = 255
                nbits += 1
    stats.append((blk, nbits))
    sheet.paste(img, ((blk % 4) * W, (blk // 4) * H))

sheet.resize((W * 4 * 2, H * 4 * 2), Image.NEAREST).save(PREVIEW)
print("块号: 像素数")
for blk, n in stats:
    print("  %2d : %d" % (blk, n))
print("预览:", PREVIEW)
