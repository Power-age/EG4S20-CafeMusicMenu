"""方案 C 定参：缓存 DFT 结果后离线扫参数，只出数值与观感图，不改 RTL。"""
import numpy as np
from map_analyze import dft_l1, msb_of, G, FS, N, NB, GAP
from sig import make_music_v2

LIN15 = np.array([min(63, max(0, 32 + ((h - 32) * 3 >> 1))) for h in range(64)])
GAMMA_C = G["C  63*(h/63)^1.5"]


def fine_of(v):
    if v <= 0:
        return 0
    m = msb_of(v)
    frac = (v >> max(m - 2, 0)) & 3 if m >= 2 else 0
    return m * 4 + frac


def collect(x):
    nb = (len(x) - N) // (N + GAP)
    M = np.zeros((nb, NB), int)
    Mc = np.zeros((nb, NB), int)
    for i in range(nb):
        mag = dft_l1(x, i * (N + GAP))
        M[i] = [msb_of(v) for v in mag]
        Mc[i] = [fine_of(v) for v in mag]
    return M, Mc


def smooth(h):
    return (np.concatenate([[h[0]], h[:-1]]) + 2 * h + np.concatenate([h[1:], [h[-1]]])) >> 2


def run_band(M, smooth_on=True, gamma=None, gate=8):
    nb = M.shape[0]
    ref = np.zeros(NB, int)
    peak = np.zeros(NB, int)
    out = np.zeros_like(M)
    for i in range(nb):
        msb = M[i]
        ok = msb >= gate
        d = msb - ref
        ref = np.where(msb > ref, msb, np.maximum(ref - 1, 0))
        h = np.clip(26 + 4 * d, 0, 63)
        h = np.where(ok, h, 0)
        if smooth_on:
            h = smooth(h)
        if gamma is not None:
            h = gamma[h]
        h = np.where(h < 3, 0, h)
        peak = np.maximum(h, peak - 1)
        out[i] = peak
    return out


def run_glob(M, Mc, gs=3, goff=44, rel=16, gamma=None, smooth_on=True, gate=8, att=2):
    """全局参考在 1/4 倍频程域跟踪帧内峰值，快起慢落。"""
    nb = M.shape[0]
    gref = 0
    peak = np.zeros(NB, int)
    out = np.zeros_like(M)
    for i in range(nb):
        f = Mc[i]
        ok = M[i] >= gate
        fmax = int(f.max())
        if not ok.any():
            h = np.zeros(NB, int)
        else:
            if fmax > gref:
                gref += max(1, (fmax - gref) // att)
            elif gref > fmax:
                gref -= max(1, (gref - fmax) // rel)
            h = np.clip(goff + gs * (f - gref), 0, 63)
            h = np.where(ok, h, 0)
        if smooth_on:
            h = smooth(h)
        if gamma is not None:
            h = gamma[h]
        h = np.where(h < 3, 0, h)
        peak = np.maximum(h, peak - 1)
        out[i] = peak
    return out


def metrics(F):
    live = F[F > 0]
    return dict(mean=live.mean(), span=(F.max(1) - F.min(1)).mean(),
                iqr=(np.percentile(F, 90, axis=1) - np.percentile(F, 10, axis=1)).mean(),
                ndif=np.abs(np.diff(F, axis=1)).mean(), zero=(F == 0).mean() * 100,
                top=(F >= 63).mean() * 100)


def show(tag, F):
    m = metrics(F)
    print(f"{tag:<38} 均高{m['mean']:5.1f} 极差{m['span']:5.1f} p90-p10{m['iqr']:5.1f}"
          f" 邻差{m['ndif']:4.1f} 贴底{m['zero']:4.1f}% 触顶{m['top']:4.1f}%")
    return m


if __name__ == "__main__":
    x = make_music_v2(12.0)
    M, Mc = collect(x)
    print(f"缓存 {M.shape[0]} 块 × {NB} 段\n")
    print("基准")
    F0 = run_band(M, gamma=None)
    show("build① 上板版（平滑+静音门）", F0)
    show("build① + A'（原步骤2）", run_band(M, gamma=LIN15))
    print("\nC1：全局参考 + 1/4 倍频程小数对数（GS = 每 1/4 倍频程像素）")
    for gs in (2, 3, 4):
        for goff in (40, 44, 48):
            show(f"  C1 GS={gs} ({gs*4}px/oct) GOFF={goff}", run_glob(M, Mc, gs=gs, goff=goff))
    print("\n加入指数提升 A'")
    for gs in (2, 3):
        for goff in (40, 44):
            show(f"  C1 GS={gs} GOFF={goff} + A'", run_glob(M, Mc, gs=gs, goff=goff, gamma=LIN15))
    print("\n释放速度（GS=3 GOFF=44 + A'）")
    for rel in (8, 16, 32, 64):
        show(f"  rel={rel}", run_glob(M, Mc, gs=3, goff=44, rel=rel, gamma=LIN15))
    print("\n攻击速度（GS=3 GOFF=44 + A'）")
    for att in (1, 2, 4, 8):
        show(f"  att={att}", run_glob(M, Mc, gs=3, goff=44, att=att, gamma=LIN15))
