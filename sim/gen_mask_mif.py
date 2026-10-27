import io
from pathlib import Path

HDL = Path(r"D:\AAA_University\Anlu\Project\src\user_source\hdl_source")
BIN = Path(r"D:\AAA_University\Anlu\Project\doc\TF卡\sub_mask_v2\TXT11.BIN")

raw = BIN.read_bytes()
assert len(raw) == 240 * 128 // 4, len(raw)

# 240x128 2bit -> 2048 x 32bit（每字 16 像素），未用地址填 0
words = []
bits = 0
acc = 0
for b in raw:
    acc |= b << bits
    bits += 8
    while bits >= 32:
        words.append(acc & 0xFFFFFFFF)
        acc >>= 32
        bits -= 32
if bits:
    words.append(acc & 0xFFFFFFFF)
words += [0] * (2048 - len(words))

mif = ["WIDTH=32;", "DEPTH=2048;", "", "ADDRESS_RADIX=HEX;", "DATA_RADIX=HEX;", "", "CONTENT BEGIN"]
for i, w in enumerate(words):
    mif.append("%04X : %08X;" % (i, w))
mif.append("END;")

out = HDL / "txt_mask.mif"
io.open(out, "w", encoding="ascii", newline="\n").write("\n".join(mif) + "\n")
print("已生成", out.name, "字数", len(words))
