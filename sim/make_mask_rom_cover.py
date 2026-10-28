"""按"封面 + 三页菜单"结构重新生成 txt_all.mif。

页序：block0/1 = 第1页（封面，空）左右；block2/3 = 原第1页；block4/5 = 原第2页；block6/7 = 原第3页。
原第4页（TXT41/42，冰美式/蓝莓麦芬）弃用。
"""
import io
from pathlib import Path

SRC = Path(r"D:\AAA_University\Anlu\Project\doc\TF卡\sub_mask_v2")
HDL = Path(r"D:\AAA_University\Anlu\Project\src\user_source\hdl_source")

BLOCK_WORDS = 240 * 128 // 32      # 每块 960 字

# None = 空块（封面页）；其余为原页号
order = [None, None, (1, 1), (1, 2), (2, 1), (2, 2), (3, 1), (3, 2)]

words = []
for item in order:
    if item is None:
        words.extend([0] * BLOCK_WORDS)
        continue
    page, k = item
    raw = (SRC / ("TXT%d%d.BIN" % (page, k))).read_bytes()
    assert len(raw) == 240 * 128 // 4
    bits = []
    for b in raw:
        for s in (0, 2, 4, 6):
            bits.append(1 if ((b >> s) & 3) >= 2 else 0)
    assert len(bits) == 240 * 128
    for i in range(0, len(bits), 32):
        w = 0
        for j in range(32):
            if bits[i + j]:
                w |= 1 << j
        words.append(w)

print("总字数:", len(words))
assert len(words) == 7680, len(words)
words += [0] * (8192 - len(words))

lines = ["WIDTH=32;", "DEPTH=8192;", "", "ADDRESS_RADIX=HEX;", "DATA_RADIX=HEX;", "", "CONTENT BEGIN"]
for i, w in enumerate(words):
    lines.append("%04X : %08X;" % (i, w))
lines.append("END;")
io.open(HDL / "txt_all.mif", "w", encoding="ascii", newline="\n").write("\n".join(lines) + "\n")
print("已生成 txt_all.mif（封面页两块为空）")
