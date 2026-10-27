"""离线复现 spectrum_engine.v 映射段，量化"柱子区分度"并对比候选曲线（只做数值取证，不动 RTL）。"""
import numpy as np

N, FS, NB, GAP = 1024, 48000.0, 40, 77
KS = [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,
      23,26,29,33,38,43,49,55,63,72,81,92,105,119,135,154,175,198,225,256]
BLK_MS = (N + GAP) / FS * 1000.0


def make_music(seconds=18.0, seed=7):
    rng = np.random.default_rng(seed)
    n = int(FS * seconds)
    W = np.fft.rfft(rng.normal(size=n))
    f = np.fft.rfftfreq(n, 1 / FS)
    f[0] = f[1]
    x = np.fft.irfft(W / np.sqrt(f), n)
    x /= np.max(np.abs(x))
    t = np.arange(n) / FS
    env = np.clip(0.55 + 0.30 * np.sin(2 * np.pi * 0.37 * t + 1.1) + 0.15 * np.sin(2 * np.pi * 2.3 * t), .05, 1.)
    beat = np.zeros(n)
    hit = rng.normal(size=n) * 0.5
    for b in np.arange(0, seconds, 0.47):
        i, L = int(b * FS), int(0.05 * FS)
        beat[i:i + L] += np.exp(-np.arange(min(L, n - i)) / (0.012 * FS)) * 0.9
    x = x * env + beat * hit
    X = np.fft.rfft(x)
    X[(f < 40) | (f > 16000)] = 0
    x = np.fft.irfft(X, n)
    return ((x / np.max(np.abs(x)) * 0.6) * 32767).astype(np.int64)


_TAB = {}
def table(k):
    if k not in _TAB:                     # Q15 三角表，预计算 40 个 k 的相位序列
        ph = np.mod(np.arange(N) * k, N)
        c = np.round(np.cos(2 * np.pi * ph / N) * 32767).astype(np.int64)
        s = np.round(np.sin(2 * np.pi * ph / N) * 32767).astype(np.int64)
        _TAB[k] = (c, s)
    return _TAB[k]


def dft_l1(x, i0):
    seg = np.zeros(N, dtype=np.int64)
    part = x[i0:i0 + N]
    seg[:len(part)] = part
    out = np.zeros(NB, dtype=np.int64)
    for b, k in enumerate(KS):
        c, s = table(k)
        out[b] = abs(int((seg * c >> 15).sum())) + abs(int((seg * s >> 15).sum()))
    return out


def msb_of(v):
    return int(v).bit_length() - 1 if v > 0 else 0


def fine_log(v):
    if v <= 0:
        return 0
    m = msb_of(v)
    return m * 4 + ((v >> max(m - 2, 0)) & 3 if m >= 2 else 0)


G = {
    "A 用户 h+(h(h-32))>>6": np.array([min(63, h + ((h * (h - 32)) >> 6)) for h in range(64)]),
    "B  h*h>>6 (gamma2)":    np.array([min(63, (h * h) >> 6) for h in range(64)]),
    "C  63*(h/63)^1.5":      np.array([min(63, round(63 * (h / 63) ** 1.5)) for h in range(64)]),
}


def run(x, ref_decay=1, fine=False, smooth=False, gamma=None, slope=4):
    nb = (len(x) - N) // (N + GAP)
    ref = np.zeros(NB, dtype=int)
    fre = np.zeros(NB, dtype=int)
    peak = np.zeros(NB, dtype=int)
    frames, msbs = [], []
    for i in range(nb):
        mag = dft_l1(x, i * (N + GAP))
        msb = np.array([msb_of(v) for v in mag])
        msbs.append(msb)
        if fine:
            fv = np.array([fine_log(v) for v in mag])
            d = fv - fre
            fre = np.where(fv > fre, fv, np.where(fre > 0, fre - (np.arange(NB) >= 0) * (1 if i % ref_decay == 0 else 0), 0))
            h = np.clip(26 + d, 0, 63)
        else:
            d = msb - ref
            dec = 1 if i % ref_decay == 0 else 0
            ref = np.where(msb > ref, msb, np.maximum(ref - dec, 0))
            h = np.clip(26 + slope * d, 0, 63)
        if smooth:
            h = (np.concatenate([[h[0]], h[:-1]]) + 2 * h + np.concatenate([h[1:], [h[-1]]])) >> 2
        if gamma is not None:
            h = gamma[h]
        h = np.where(h < 3, 0, h)
        peak = np.maximum(h, peak - 1)
        frames.append(peak.astype(int))
    return np.array(frames), np.array(msbs)


def report(tag, F):
    live = F[F > 0]
    rng_pf = (F.max(1) - F.min(1)).mean()          # 帧内跨条极差
    std_pf = F.std(1).mean()                       # 帧内跨条标准差
    ndif = np.abs(np.diff(F, axis=1)).mean()       # 相邻条平均差（越小越"山丘"）
    uniq = np.mean([len(np.unique(f)) for f in F])  # 帧内不同高度个数
    print(f"{tag:<30} 均高{live.mean():5.1f}px  帧内极差{rng_pf:5.1f}  帧内std{std_pf:4.1f}"
          f"  邻差{ndif:4.1f}  帧内档位{uniq:4.1f}  触顶{(F>=63).mean()*100:4.1f}%")


def main():
    x = make_music()
    print(f"合成音乐信号 {len(x)/FS:.1f}s  块周期 {BLK_MS:.1f}ms -> 更新率 {FS/(N+GAP):.1f}Hz\n")
    F0, M = run(x)
    print("各频段平均 msb（越大越响；相差 1 = 2 倍幅度）")
    for i in range(0, NB, 10):
        print("  band %2d-%2d  " % (i, i + 9) + " ".join(f"{v:5.1f}" for v in M.mean(0)[i:i + 10]))
    print(f"  全频段 msb 极差 = {M.mean(0)[0]-M.mean(0)[-1]:.2f} 个倍频程\n")

    print("当前实现的高度分布（最终条高 - 峰值保持后）")
    v, c = np.unique(F0, return_counts=True)
    for q in [10, 25, 50, 75, 90, 99]:
        print(f"  p{q:>2} = {np.percentile(F0[F0>0], q):5.1f}px", end="")
    print()
    print("  Top8 高度: " + "  ".join(f"{v[i]}px×{c[i]}" for i in np.argsort(-c)[:8]) + "\n")

    print("候选映射对比（数值为全片均值）")
    report("V0 当前", F0)
    report("V1 +3点平滑", run(x, smooth=True)[0])
    for gn, gt in G.items():
        report(f"V2{gn[0]} +平滑+{gn[2:]}", run(x, smooth=True, gamma=gt)[0])
    print()
    print("AGC 释放时间对比（不带 gamma，单变量看参考衰减速率）")
    for rd in [1, 2, 4, 8, 16, 32]:
        report(f"  ref 每 {rd} 块降 1 ({rd*BLK_MS:5.0f}ms)", run(x, ref_decay=rd, smooth=True)[0])
    print()
    print("组合对比")
    report("V3 = 慢释放8 + 平滑", run(x, ref_decay=8, smooth=True)[0])
    report("V3 + gammaC", run(x, ref_decay=8, smooth=True, gamma=G["C  63*(h/63)^1.5"])[0])
    report("V3 + gammaA(用户式)", run(x, ref_decay=8, smooth=True, gamma=G["A 用户 h+(h(h-32))>>6"])[0])
    report("V4 = V3 + gammaC + 小数对数", run(x, ref_decay=8, smooth=True, fine=True, gamma=G["C  63*(h/63)^1.5"])[0])
    report("V5 = V4 + 斜率4->6", run(x, ref_decay=8, smooth=True, fine=True, gamma=G["C  63*(h/63)^1.5"], slope=6)[0])
    print()
    print("静音（音量 0）3 秒：柱子是否应归零")
    xz = np.zeros(int(FS * 3), dtype=np.int64)
    for tag, kw in [("V0 当前", {}), ("V4 方案", dict(ref_decay=8, smooth=True, fine=True, gamma=G["C  63*(h/63)^1.5"]))]:
        F, _ = run(xz, **kw)
        idx = [0, int(.5 / (BLK_MS / 1000)), int(1.5 / (BLK_MS / 1000)), int(2.8 / (BLK_MS / 1000))]
        print(f"  {tag:<8} 平均条高 @0/0.5/1.5/2.8s = " + " / ".join(f"{F[min(i,len(F)-1)].mean():4.1f}px" for i in idx))


if __name__ == "__main__":
    main()
