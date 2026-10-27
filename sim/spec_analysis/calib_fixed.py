"""固定参考（无 AGC）量程标定：柱高随音量变化，同时按 vol=15 满档标定。"""
import numpy as np
from pathlib import Path

GAM = np.array([min(63, max(0, 32 + ((h - 32) * 3 >> 1))) for h in range(64)])
NB = 40
OUT = Path(r"D:\AAA_University\Anlu\Project\sim\spec_analysis")


def simulate_fixed(F7, ref, goff, gs, gate=32, pk=1, emph=0):
    nb = F7.shape[0]
    peak = np.zeros(NB, int)
    out = np.zeros_like(F7)
    for i in range(nb):
        f = F7[i]
        h = np.clip(goff + gs * (f - ref), 0, 63)
        h = np.where(f >= gate, h, 0)
        h = (np.concatenate([[h[0]], h[:-1]]) + 2 * h + np.concatenate([h[1:], [h[-1]]])) >> 2
        h = GAM[h]
        h = np.where(h < 3, 0, h)
        peak = np.maximum(h, peak - pk)
        if emph:
            d = np.abs(np.arange(NB) - ((i * 0.5) % NB))
            cw = np.maximum(0, 8 - d)
            out[i] = np.where(peak > 0, np.clip(peak + (cw * emph / 8).astype(int), 0, 63), peak)
        else:
            out[i] = peak
    return out


def score(tag, F, show=True):
    live = F[F > 0]
    iqr = (np.percentile(F, 90, axis=1) - np.percentile(F, 10, axis=1)).mean()
    span = (F.max(1) - F.min(1)).mean()
    m = dict(mean=live.mean() if live.size else 0, span=span, iqr=iqr,
             zero=(F == 0).mean() * 100, top=(F >= 63).mean() * 100)
    if show:
        print("%-30s 均高%5.1f 极差%5.1f 散布%5.1f 贴底%5.1f%% 触顶%4.1f%%"
              % (tag, m["mean"], m["span"], m["iqr"], m["zero"], m["top"]))
    return m


if __name__ == "__main__":
    F15 = np.load(OUT / "fine_huoyuanjia.npy")
    print("vol=15 满档，扫 参考点 REF / 斜率 GS / 偏置 GOFF（h = GOFF + GS·(fine − REF)）")
    for ref in (88, 92, 96):
        for goff, gs in ((54, 2), (52, 2), (48, 2), (54, 3), (44, 3)):
            score("  REF=%d GOFF=%d GS=%d" % (ref, goff, gs), simulate_fixed(F15, ref, goff, gs))
    print("\n选定 REF=92 GOFF=52 GS=2：音量档响应（每档 6dB ≈ 4 个 1/4 倍频程单位）")
    for tag, shift in [("vol=15", 0), ("vol=12", -4), ("vol=8", -8), ("vol=4", -12), ("vol=1", -16)]:
        score("  " + tag, simulate_fixed(np.clip(F15 + shift, 0, 127), 92, 52, 2))
