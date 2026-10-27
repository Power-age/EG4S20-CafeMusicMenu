import numpy as np
from sig import make_music_v2
from plan_c2 import collect, LIN15, metrics


def run_glob_pk(M, Mc, gs=3, goff=44, gamma=None, pk=1, gate=8, att=2, rel=16):
    nb = M.shape[0]
    gref = 0
    peak = np.zeros(40, int)
    out = np.zeros_like(M)

    def sm(h):
        return (np.concatenate([[h[0]], h[:-1]]) + 2 * h + np.concatenate([h[1:], [h[-1]]])) >> 2

    for i in range(nb):
        f = Mc[i]
        ok = M[i] >= gate
        fmax = int(f.max())
        if not ok.any():
            h = np.zeros(40, int)
        else:
            if fmax > gref:
                gref += max(1, (fmax - gref) // att)
            elif gref > fmax:
                gref -= max(1, (gref - fmax) // rel)
            h = np.clip(goff + gs * (f - gref), 0, 63)
            h = np.where(ok, h, 0)
        h = sm(h)
        if gamma is not None:
            h = gamma[h]
        h = np.where(h < 3, 0, h)
        peak = np.maximum(h, peak - pk)
        out[i] = peak
    return out


def show(tag, F):
    m = metrics(F)
    print("%-30s 均高%5.1f 极差%5.1f p90-p10%5.1f 邻差%4.1f 贴底%4.1f%%"
          % (tag, m["mean"], m["span"], m["iqr"], m["ndif"], m["zero"]))


x = make_music_v2(12.0)
M, Mc = collect(x)
print("C1 GS=3 GOFF=44 + A'，峰值保持衰减速度（纯参数，0 LUT）")
for pk in [1, 2, 4, 8, 16, 63]:
    ms = 64.0 / pk / 44.0 * 1000
    show("  pk=%2d (落满 %4.0fms)" % (pk, ms), run_glob_pk(M, Mc, gamma=LIN15, pk=pk))
print()
for gs in [2, 3, 4]:
    for pk in [1, 4, 8]:
        show("  GS=%d pk=%d" % (gs, pk), run_glob_pk(M, Mc, gs=gs, gamma=LIN15, pk=pk))
