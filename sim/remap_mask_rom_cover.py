"""在既有 txt_all.mif 上按"块"搬运，得到 封面页(空) + 原第1~3页 的新 ROM。

块结构（部署版）：4096 字 × 32bit，每块 512 字，8 块 = {页号[1:0], 左右}。
旧布局：块 0..7 = 第1页左/右, 第2页左/右, 第3页左/右, 第4页左/右。
新布局：块 0/1 = 空（封面页）；块 2/3 = 旧块 0/1；块 4/5 = 旧块 2/3；块 6/7 = 旧块 4/5；旧块 6/7（冰美式/蓝莓麦芬）丢弃。
"""
import io

OLD = r"D:\AAA_University\Anlu\Project\sim\backups\txt_all_before_cover.mif"
OUT = r"D:\AAA_University\Anlu\Project\src\user_source\hdl_source\txt_all.mif"

BLOCK = 512
NBLK = 8

vals = {}
for line in io.open(OLD, encoding="ascii"):
    line = line.strip()
    if not line or ":" not in line:
        continue
    head, tail = line.split(":", 1)
    head = head.strip()
    tail = tail.strip().rstrip(";")
    if not head or len(head) != 4:
        continue
    try:
        addr = int(head, 16)
        val = int(tail, 16)
    except ValueError:
        continue
    vals[addr] = val

print("读入字数:", len(vals))
assert len(vals) == 4096, len(vals)

def block(i):
    base = i * BLOCK
    return [vals.get(base + k, 0) for k in range(BLOCK)]

blank = [0] * BLOCK
new = []
new += blank + blank                     # 封面页（左/右）
new += block(0) + block(1)               # 原第1页 → 新第2页
new += block(2) + block(3)               # 原第2页 → 新第3页
new += block(4) + block(5)               # 原第3页 → 新第4页
assert len(new) == 4096, len(new)

lines = ["WIDTH=32;", "DEPTH=4096;", "", "ADDRESS_RADIX=HEX;", "DATA_RADIX=HEX;", "", "CONTENT BEGIN"]
for i, w in enumerate(new):
    lines.append("%04X : %08X;" % (i, w))
lines.append("END;")
io.open(OUT, "w", encoding="ascii", newline="\n").write("\n".join(lines) + "\n")

# 自检：新块2..7 应与旧块0..5 逐字相同
ok = all(new[(2 + j) * BLOCK:(3 + j) * BLOCK] == block(j) for j in range(6))
print("块搬运自检:", ok, "| 封面块全零:", all(w == 0 for w in new[:2 * BLOCK]))
print("已生成 txt_all.mif（DEPTH=4096）")
