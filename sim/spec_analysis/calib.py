"""用真曲目标定频谱量程：统计 40 段对数电平分布，反解 GOFF / GS / 强调上限。"""
import sys
import wave
import numpy as np
from map_analyze import dft_l1, msb_of, N, NB, GAP

FS_TARGET = 48000


def load_wav(path, max_sec=None):
    with wave.open(path, "rb") as w:
        assert w.getframerate() == FS_TARGET, w.getframerate()
        assert w.getsampwidth() == 2
        nch = w.getnchannels()
        n = w.getnframes() if max_sec is None else min(w.getnframes(), int(max_sec * FS_TARGET))
        raw = w.readframes(n)
    x = np.frombuffer(raw, dtype="<i2").astype(np.int64)
    if nch > 1:
        x = x.reshape(-1, nch).mean(axis=1).astype(np.int64)
    return x


def fine_of(v):
    if v <= 0:
        return 0
    m = msb_of(v)
    return m * 4 + ((v >> max(m - 2, 0)) & 3 if m >= 2 else 0)


def collect(x, step=2):
    nb = (len(x) - N) // (N + GAP)
    rows = []
    for i in range(0, nb, step):
        mag = dft_l1(x, i * (N + GAP))
        rows.append([fine_of(v) for v in mag])
    return np.array(rows)


def simulate(F7, goff, gs, gate=32, att=2, pk=1, emph=0, emph_frac=0.30):
    """F7: 每块 40 段 fine 值。返回最终显示高度（含峰值保持与强调）。"""
    nb = F7.shape[0]
    gref = 80
    peak = np.zeros(NB, int)
    out = np.zeros_like(F7)
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
        h = (np.concatenate([[h[0]], h[:-1]]) + 2 * h + np.concatenate([h[1:], [h[-1]]])) >> 2
        h = np.array([min(63, max(0, 32 + ((int(v) - 32) * 3 >> 1))) for v in h])
        h = np.where(h < 3, 0, h)
        peak = np.maximum(h, peak - pk)
        if emph:
            ph = (i * 0.5) % NB
            d = np.abs(np.arange(NB) - ph)
            cw = np.maximum(0, 8 - d)
            add = (cw * emph / 8).astype(int)
            peak = np.where(peak > 0, np.clip(peak + add, 0, 63), peak)
        out[i] = peak
    return out


def report(tag, F):
    live = F[F > 0]
    iqr = (np.percentile(F, 90, axis=1) - np.percentile(F, 10, axis=1)).mean()
    span = (F.max(1) - F.min(1)).mean()
    print("%-34s 均高%5.1f 极差%5.1f p90-p10%5.1f 贴底%5.1f%% 触顶%4.1f%%"
          % (tag, live.mean(), span, iqr, (F == 0).mean() * 100, (F >= 63).mean() * 100))


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else r"D:\AAA_University\Anlu\Project\sim\spec_analysis\huoyuanjia_48k.wav"
    x = load_wav(path)
    print("样本 %d，时长 %.1fs" % (len(x), len(x) / FS_TARGET))
    F7 = collect(x)
    print("块数 %d，fine 范围 %d..%d（1/4 倍频程）" % (F7.shape[0], F7.min(), F7.max()))
    np.save(r"D:\AAA_University\Anlu\Project\sim\spec_analysis\calib_fine.npy", F7)

    per_band = F7.mean(axis=0)
    print("\n各频段平均 fine：")
    for i in range(0, NB, 10):
        print("  band %2d-%2d  " % (i, i + 9) + " ".join("%5.1f" % v for v in per_band[i:i + 10]))

    goff, gs = 48, 3
    gref = 80
    d = []
    for i in range(F7.shape[0]):
        fmax = int(F7[i].max())
        if fmax > gref:
            gref += max(1, (fmax - gref) // 2)
        elif gref > fmax:
            gref -= 1
        d.append(F7[i] - gref)
    d = np.array(d)
    print("\n(fine - gref) 分布：p1=%.1f p5=%.1f p50=%.1f p95=%.1f p99.5=%.1f max=%.1f"
          % tuple(np.percentile(d, [1, 5, 50, 95, 99.5]).tolist() + [d.max()]))
    print("  → 上方余量：fine-gref ≥ 5 就撞顶，实测超过该值的占比 %.1f%%"
          % ((d >= 5).mean() * 100))

    print("\n当前参数（GOFF=48, GS=3, 强调16）")
    report("  现状", simulate(F7, 48, 3, emph=16))
    print("\n候选标定（保证 GOFF + 强调 ≤ 62）")
    for goff, gs in [(42, 3), (44, 3), (40, 4), (38, 4), (44, 4), (36, 5)]:
        em = min(16, 62 - goff)
        report("  GOFF=%d GS=%d 强调%d" % (goff, gs, em), simulate(F7, goff, gs, emph=em))
    print("\n不带强调（0 档）参考")
    for goff, gs in [(42, 3), (44, 3), (40, 4)]:
        report("  GOFF=%d GS=%d 无强调" % (goff, gs), simulate(F7, goff, gs, emph=0))
