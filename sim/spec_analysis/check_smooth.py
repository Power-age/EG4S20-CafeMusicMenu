import re
import numpy as np

P = r"D:\AAA_University\Anlu\Project\sim\work_e15\spec_dbg2_out.txt"
rows, outs = [], []
for line in open(P, encoding="utf-8"):
    if line.startswith("OUT"):
        outs.append([int(v) for v in line.split()[2:]])
    elif not line.startswith("#"):
        rows.append([int(v) for v in line.split()])
rows = np.array(rows)

bad = 0
blocks = sorted(set(rows[:, 0]))
for b in blocks:
    r = rows[rows[:, 0] == b]
    if len(r) != 42:
        print(f"block {b}: 迭代数 {len(r)} != 42")
        bad += 1
        continue
    h_rd = r[:, 2]
    sm1, sm2, sm_val, w_idx = r[:, 3], r[:, 4], r[:, 5], r[:, 6]
    for i in range(1, 41):
        exp = (sm2[i] + 2 * sm1[i] + h_rd[i]) >> 2
        if exp != sm_val[i]:
            print(f"block {b} i={i}: sm_val={sm_val[i]} 期望 {exp} (sm2={sm2[i]} sm1={sm1[i]} h_rd={h_rd[i]})")
            bad += 1
        if w_idx[i] != i - 1:
            print(f"block {b} i={i}: w_idx={w_idx[i]} 期望 {i-1}")
            bad += 1
    if h_rd[40] != sm1[40]:
        print(f"block {b} i=40 镜像失败 h_rd={h_rd[40]} sm1={sm1[40]}")
        bad += 1
    bh = h_rd[0:40]
    if sm_val[1] != (3 * bh[0] + bh[1]) >> 2:
        print(f"block {b} 左端镜像不符: {sm_val[1]} vs {(3*bh[0]+bh[1])>>2}")
        bad += 1
    if sm_val[40] != (bh[38] + 3 * bh[39]) >> 2:
        print(f"block {b} 右端镜像不符: {sm_val[40]} vs {(bh[38]+3*bh[39])>>2}")
        bad += 1
    if np.any(r[0, 7:8] != 0) and b == blocks[0]:
        pass

print(f"检查 {len(blocks)} 个块、每块 40 次平滑：{'全部通过' if bad == 0 else f'{bad} 处不符'}")

O = np.array(outs)
print("\n各块最终 40 条高度（峰值保持后）")
for b in range(min(len(O), 14)):
    v = O[b]
    print(f"  blk{b:>2} min={v.min():2d} max={v.max():2d}  " + " ".join(f"{x:2d}" for x in v[:20]))
print("  ...")
for b in range(max(0, len(O) - 4), len(O)):
    v = O[b]
    print(f"  blk{b:>2} min={v.min():2d} max={v.max():2d}  " + " ".join(f"{x:2d}" for x in v[:20]))
