"""方案 C（全局参考 AGC）参数扫描：与当前实现/build① 对比，指标含散布、贴底、触顶。"""
import numpy as np
from map_analyze import dft_l1, msb_of, G, FS, N, NB, GAP
from sig import make_music_v2

GAMMA_A = G["A 用户 h+(h(h-32))>>6"]
GAMMA_C = G["C  63*(h/63)^1.5"]
LIN15 = np.array([min(63, max(0, 32 + ((h - 32) * 3 >> 1))) for h in range(64)])


def run(x, mode="band", slope=4, off=26, gslope=6, goff=48, gdecay=32,
        smooth=True, gamma=None, gate=8, pk_decay=1):
    nb = (len(x) - N) // (N + GAP)
    ref = np.zeros(NB, int)
    gref = 0
    gcnt = 0
    peak = np.zeros(NB, int)
    out = []
    for i in range(nb):
        mag = dft_l1(x, i * (N + GAP))
        msb = np.array([msb_of(v) for v in mag])
        blk_max = int(msb.max())
        ok = msb >= gate
        if ok.any():
            gcnt += 1
            if blk_max > gref:
                gref = blk_max; gcnt = 0
            elif gcnt >= gdecay and gref > 0:
                gref -= 1; gcnt = 0
            if mode == "band":
                d = msb - ref
                ref = np.where(msb > ref, msb, np.maximum(ref - 1, 0))
                h = off + slope * d
            elif mode == "glob":
                h = goff + gslope * (msb - gref)
            elif mode == "hyb":
                d = msb - ref
                ref = np.where(msb > ref, msb, np.maximum(ref - 1, 0))
                h = goff + gslope * (msb - gref) + 2 * d
            h = np.clip(h, 0, 63)
            h = np.where(ok, h, 0)
        else:
            h = np.zeros(NB, int)
        if smooth:
            h = (np.concatenate([[h[0]], h[:-1]]) + 2 * h + np.concatenate([h[1:], [h[-1]]])) >> 2
            h = (h + 1) >> 1 if False else h
        if gamma is not None:
            h = gamma[h]
        h = np.where(h < 3, 0, h)
        peak = np.maximum(h, peak - pk_decay)
        out.append(peak.copy())
    return np.array(out)


def show(tag, F):
    live = F[F > 0]
    iqr = (np.percentile(F, 90, axis=1) - np.percentile(F, 10, axis=1)).mean()
    span = (F.max(1) - F.min(1)).mean()
    print(f"{tag:<34} 均高{live.mean():5.1f}  极差{span:5.1f}  p90-p10{iqr:5.1f}"
          f"  邻差{np.abs(np.diff(F,axis=1)).mean():4.1f}  贴底{(F==0).mean()*100:4.1f}%"
          f"  触顶{(F>=63).mean()*100:4.1f}%")


x = make_music_v2(12.0)
print(f"信号 {len(x)/FS:.0f}s，块 {FS/(N+GAP):.0f} 次/秒\n")
print("当前 / build①（逐频段 AGC）")
show("build① = 平滑+绝对门", run(x, mode="band", smooth=True))
show("build① + gammaA'", run(x, mode="band", smooth=True, gamma=LIN15))
print("\n方案 C1：全局参考 AGC + 平滑")
for gs, go in [(4, 44), (5, 46), (6, 48), (7, 50), (8, 52)]:
    show(f"  C1 s{gs} o{go}", run(x, mode="glob", gslope=gs, goff=go, smooth=True))
print("\n方案 C1 + 指数提升")
for gs, go in [(5, 46), (6, 48), (7, 50)]:
    show(f"  C1 s{gs} o{go} + A'", run(x, mode="glob", gslope=gs, goff=go, smooth=True, gamma=LIN15))
    show(f"  C1 s{gs} o{go} + g1.5", run(x, mode="glob", gslope=gs, goff=go, smooth=True, gamma=GAMMA_C))
print("\n方案 C2：全局 + 弱逐段（混合）")
for gs, go in [(5, 46), (6, 48)]:
    show(f"  C2 s{gs} o{go} + A'", run(x, mode="hyb", gslope=gs, goff=go, smooth=True, gamma=LIN15))
print("\n参考衰减周期（C1 s6o48 + A'）")
for gd in [8, 16, 32, 64, 128]:
    show(f"  gdecay={gd} ({gd*GAP2:.2f}s)" if False else f"  gdecay={gd}", 
         run(x, mode="glob", gslope=6, goff=48, gdecay=gd, smooth=True, gamma=LIN15))
