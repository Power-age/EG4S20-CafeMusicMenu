"""按真曲目重扫量程参数（强调层只在显示侧叠加，不进峰值状态）。"""
import numpy as np
from calib import load_wav, report

GAM = np.array([min(63, max(0, 32 + ((h - 32) * 3 >> 1))) for h in range(64)])
NB = 40


def simulate(F7, goff, gs, emph=0, gate=32, att=2, pk=1, smooth=True):
    nb = F7.shape[0]
    gref = 80
    peak = np.zeros(NB, int)
    out = np.zeros_like(F7)
    t = np.arange(nb)
    for i in range(nb):
        f = F7[i]
        fmax = int(f.max())
        if fmax < gate:
            h = np.zeros(NB, int)
        else:
            if fmax > gref:
                gref += max(1, (fmax - gref) // att)
            elif gref > fmax:
                gref -= 1
            h = np.clip(goff + gs * (f - gref), 0, 63)
        if smooth:
            h = (np.concatenate([[h[0]], h[:-1]]) + 2 * h + np.concatenate([h[1:], [h[-1]]])) >> 2
        h = GAM[h]
        h = np.where(h < 3, 0, h)
        peak = np.maximum(h, peak - pk)
        if emph:
            d = np.abs(np.arange(NB) - ((i * 0.5) % NB))
            cw = np.maximum(0, 8 - d)
            disp = np.where(peak > 0, np.clip(peak + (cw * emph / 8).astype(int), 0, 63), peak)
        else:
            disp = peak
        out[i] = disp
    return out


def score(tag, F):
    live = F[F > 0]
    iqr = (np.percentile(F, 90, axis=1) - np.percentile(F, 10, axis=1)).mean()
    span = (F.max(1) - F.min(1)).mean()
    top = (F >= 63).mean() * 100
    zero = (F == 0).mean() * 100
    print("%-26s 均高%5.1f 极差%5.1f 散布%5.1f 贴底%5.1f%% 触顶%4.1f%%" %
          (tag, live.mean(), span, iqr, zero, top))
    return dict(mean=live.mean(), span=span, iqr=iqr, zero=zero, top=top)


if __name__ == "__main__":
    F7 = np.load(r"D:\AAA_University\Anlu\Project\sim\spec_analysis\calib_fine.npy")
    print("块数 %d（真曲目 4:38，48kHz）\n" % F7.shape[0])

    print("=== 现上板版（GOFF=48 GS=3）===")
    score("  0 档（无强调）", simulate(F7, 48, 3, 0))
    for em in (8, 12, 16):
        score("  %d 档（+%d）" % ([0, 8, 12, 16].index(em), em), simulate(F7, 48, 3, em))

    print("\n=== 候选：降斜率（GS=2，8px/倍频程，可容 8 个倍频程动态）===")
    for goff in (52, 56, 58, 60):
        em = min(16, 62 - goff)
        score("  GOFF=%d GS=2 0档" % goff, simulate(F7, goff, 2, 0))
        score("  GOFF=%d GS=2 强调%d" % (goff, em), simulate(F7, goff, 2, em))

    print("\n=== 候选：GS=3 只压 GOFF ===")
    for goff in (40, 44):
        em = 62 - goff if 62 - goff < 16 else 16
        score("  GOFF=%d GS=3 强调%d" % (goff, em), simulate(F7, goff, 3, em))

    print("\n=== 参考释放速度（GOFF=58 GS=2）===")
    for att in (1, 2, 4):
        score("  att=%d" % att, simulate(F7, 58, 2, 6, att=att))
    print("\n=== 峰值保持速度（GOFF=58 GS=2）===")
    for pk in (1, 2, 3):
        score("  pk=%d" % pk, simulate(F7, 58, 2, 6, pk=pk))
