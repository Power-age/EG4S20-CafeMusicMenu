"""C1 底图 + 人工差异增强：三种调制方式的定量对比（不动 RTL）。"""
import numpy as np
from sig import make_music_v2
from plan_c2 import collect, run_band, LIN15, metrics

NB = 40


def base_c1(M, Mc, gs=2, goff=48, pk=1, gate=8, att=2):
    nb = M.shape[0]
    gref, peak, out = 0, np.zeros(NB, int), np.zeros_like(M)
    for i in range(nb):
        f, ok, fmax = Mc[i], M[i] >= gate, int(Mc[i].max())
        if not ok.any():
            h = np.zeros(NB, int)
        else:
            if fmax > gref:
                gref += max(1, (fmax - gref) // att)
            elif gref > fmax:
                gref -= 1
            h = np.clip(goff + gs * (f - gref), 0, 63)
            h = np.where(ok, h, 0)
        h = (np.concatenate([[h[0]], h[:-1]]) + 2 * h + np.concatenate([h[1:], [h[-1]]])) >> 2
        h = LIN15[h]
        h = np.where(h < 3, 0, h)
        peak = np.maximum(h, peak - pk)
        out[i] = peak
    return out


def modulate(F, kind, amp, wb=8, speed=1.0, phase0=0):
    nb = F.shape[0]
    out = np.zeros_like(F)
    b = np.arange(NB)
    tbl = np.array([0, 7, 2, 9, 1, 6, 3, 8])
    for i in range(nb):
        h = F[i].astype(int)
        if kind == "crest":
            ph = (phase0 + speed * i) % NB
            d = np.abs(b - ph)
            w = np.maximum(0, wb - d)
            off = (w * amp) // wb
            h = np.where(h > 0, h + off, h)
        elif kind == "comb":
            ph = int(phase0 + speed * i) % 8
            h = np.where(h > 0, h + tbl[(b + ph) % 8] * amp // 8, h)
        elif kind == "mult":
            ph = (phase0 + speed * i) % NB
            d = np.abs(b - ph)
            w = np.maximum(0, wb - d)
            g = 16 + (w * amp) // wb
            h = (h * g) >> 4
        out[i] = np.clip(h, 0, 63)
    return out


def report(tag, F):
    m = metrics(F)
    tstd = F.std(axis=0).mean()
    jump = np.abs(np.diff(F, axis=0)).mean()
    print("%-40s 均高%5.1f 极差%5.1f p90-p10%5.1f 时间波动%4.1f 块间跳变%4.1f 贴底%4.1f%%"
          % (tag, m["mean"], m["span"], m["iqr"], tstd, jump, m["zero"]))
    return m


if __name__ == "__main__":
    x = make_music_v2(12.0)
    M, Mc = collect(x)
    print("基准")
    report("现上板版", run_band(M))
    F2 = base_c1(M, Mc, gs=2)
    report("C1 稳妥 GS2/GOFF48/pk1", F2)
    report("C1 GS3/GOFF48/pk1", base_c1(M, Mc, gs=3))
    print("\n加「扫过的强调峰」(crest)")
    for amp, wb, sp in [(8, 8, 1.0), (12, 8, 1.0), (12, 10, 0.5), (16, 8, 1.0), (16, 10, 0.5)]:
        report("  crest amp=%2d wb=%2d speed=%.1f" % (amp, wb, sp),
               modulate(F2, "crest", amp, wb, sp))
    print("\n加「轮转梳齿」(comb，直接对应“特定列轮流升高”)")
    for amp in [6, 8, 12]:
        report("  comb amp=%2d" % amp, modulate(F2, "comb", amp, speed=1.0))
    print("\n加「乘性强调」(乘法，峰越高放大越多)")
    for amp in [6, 8, 12]:
        report("  mult amp=%2d" % amp, modulate(F2, "mult", amp, wb=10, speed=0.5))
