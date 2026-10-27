"""补充对比：线性展开器、全局参考 AGC、小数对数、斜率。复用 map_analyze 的 DFT 与指标口径。"""
import numpy as np
from map_analyze import make_music, dft_l1, msb_of, fine_log, G, FS, N, NB, GAP


def metrics(F):
    live = F[F > 0]
    inst = np.percentile(F, 90, axis=1) - np.percentile(F, 10, axis=1)
    return dict(mean=live.mean(), span=(F.max(1) - F.min(1)).mean(), iqr=inst.mean(),
                ndif=np.abs(np.diff(F, axis=1)).mean(), top=(F >= 63).mean() * 100)


def run(x, mode="v0", decay=1, slope=4, smooth=False, gamma=None, off=26, gslope=6, goff=48, gdecay=32):
    nb = (len(x) - N) // (N + GAP)
    ref = np.zeros(NB, int)
    gref = 0
    peak = np.zeros(NB, int)
    out = []
    for i in range(nb):
        mag = dft_l1(x, i * (N + GAP))
        msb = np.array([msb_of(v) for v in mag])
        if mode == "v0":
            d = msb - ref
            ref = np.where(msb > ref, msb, np.maximum(ref - (1 if i % decay == 0 else 0), 0))
            h = np.clip(off + slope * d, 0, 63)
        elif mode == "fine":
            fre = getattr(run, "_fre", None)
            if fre is None or len(fre) != NB:
                fre = np.zeros(NB, int); run._fre = fre
            fv = np.array([fine_log(v) for v in mag])
            d = fv - fre
            fre = np.where(fv > fre, fv, np.maximum(fre - (1 if i % decay == 0 else 0), 0))
            run._fre = fre
            h = np.clip(off + d, 0, 63)
        elif mode == "glob":
            gref = max(int(msb.max()), gref - (1 if i % gdecay == 0 else 0))
            h = np.clip(goff + gslope * (msb - gref), 0, 63)
        elif mode == "hyb":            # 全局参考 + 弱逐段归一化
            gref = max(int(msb.max()), gref - (1 if i % gdecay == 0 else 0))
            d = msb - ref
            ref = np.where(msb > ref, msb, np.maximum(ref - (1 if i % decay == 0 else 0), 0))
            h = np.clip(goff + gslope * (msb - gref) + 2 * d, 0, 63)
        if smooth:
            h = (np.concatenate([[h[0]], h[:-1]]) + 2 * h + np.concatenate([h[1:], [h[-1]]])) >> 2
        if gamma is not None:
            h = gamma[h]
        h = np.where(h < 3, 0, h)
        peak = np.maximum(h, peak - 1)
        out.append(peak)
    return np.array(out)


LIN15 = np.array([min(63, max(0, 32 + ((h - 32) * 3 >> 1))) for h in range(64)])
rows = []


def show(tag, F):
    m = metrics(F)
    rows.append((tag, m))
    print(f"{tag:<34} 均高{m['mean']:5.1f}  帧内极差{m['span']:5.1f}  帧内p90-p10{m['iqr']:5.1f}"
          f"  邻差{m['ndif']:4.1f}  触顶{m['top']:4.1f}%")


x = make_music()
print("基准与已确认候补")
show("V0 当前", run(x))
show("V1 +平滑", run(x, smooth=True))
show("V2A +平滑+用户gammaA", run(x, smooth=True, gamma=G["A 用户 h+(h(h-32))>>6"]))
show("V2A' +平滑+线性1.5展开器", run(x, smooth=True, gamma=LIN15))
print("\n零成本/低成本变体")
show("斜率4->6 (无gamma)", run(x, slope=6, smooth=True))
show("斜率4->8 (无gamma)", run(x, slope=8, smooth=True))
show("小数对数 步长1px (无gamma)", run(x, mode="fine", smooth=True))
show("小数对数 + 斜率8", run(x, mode="fine", slope=8, smooth=True))
print("\n全局参考 AGC（替换逐频段归一化）")
for gs, go in [(5, 46), (6, 48), (7, 50), (8, 52)]:
    show(f"glob slope{gs} off{go} (无gamma)", run(x, mode="glob", gslope=gs, goff=go, smooth=True))
show("glob s6o48 + gammaA", run(x, mode="glob", gslope=6, goff=48, smooth=True, gamma=G["A 用户 h+(h(h-32))>>6"]))
show("glob s7o50 + gammaA", run(x, mode="glob", gslope=7, goff=50, smooth=True, gamma=G["A 用户 h+(h(h-32))>>6"]))
show("hyb glob6+2*band + gammaA", run(x, mode="hyb", gslope=6, goff=48, smooth=True, gamma=G["A 用户 h+(h(h-32))>>6"]))

print("\n静音 3s（音量 0）平均条高 @0/0.5/1.5/2.8s")
xz = np.zeros(int(FS * 3), dtype=np.int64)
for tag, kw in [("V0 当前", {}), ("V1 平滑", dict(smooth=True)),
                ("V2A 平滑+gammaA", dict(smooth=True, gamma=G["A 用户 h+(h(h-32))>>6"])),
                ("glob s6o48+平滑", dict(mode="glob", gslope=6, goff=48, smooth=True))]:
    F = run(xz, **kw)
    idx = [0, int(.5/((N+GAP)/FS)), int(1.5/((N+GAP)/FS)), int(2.8/((N+GAP)/FS))]
    print(f"  {tag:<18} " + " / ".join(f"{F[min(i,len(F)-1)].mean():4.1f}px" for i in idx))
