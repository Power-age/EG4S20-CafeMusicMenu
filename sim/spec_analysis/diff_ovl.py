"""比对窗口改动前后整帧像素差异，确认差异只落在 y 400~413 的 x 362~367。"""
from pathlib import Path

D = Path(r"D:\AAA_University\Anlu\Project\sim\work_e15")


def load(p):
    d = {}
    for line in p.read_text(encoding="ascii").splitlines():
        xs, ys, c = line.split()
        d[(int(xs), int(ys))] = c
    return d


old = load(D / "ovl_dump_old.txt")
new = load(D / "ovl_dump_new.txt")
assert old.keys() == new.keys(), "坐标集不一致"

diff = [(k, old[k], new[k]) for k in old if old[k] != new[k]]
xs = sorted({k[0] for k, _, _ in diff})
ys = sorted({k[1] for k, _, _ in diff})
print("差异像素数:", len(diff))
print("x 范围:", (min(xs), max(xs)) if xs else None)
print("y 范围:", (min(ys), max(ys)) if ys else None)
inside = [d for d in diff if 362 <= d[0][0] <= 367 and 400 <= d[0][1] <= 413]
print("落在预期区域 (x362~367, y400~413) 的比例: %.1f%%" % (100.0 * len(inside) / max(1, len(diff))))
print("\n样例（前 8 个差异）:")
for k, o, n in diff[:8]:
    print("  x=%3d y=%3d  旧=%s  新=%s" % (k[0], k[1], o, n))
