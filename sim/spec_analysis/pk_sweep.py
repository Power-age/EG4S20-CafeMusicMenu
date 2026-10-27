import numpy as np
from map_analyze import N, NB, GAP, FS
from sig import make_music_v2
from plan_c import run, LIN15, GAMMA_C

x = make_music_v2(12.0)
def show(tag, F):
    live = F[F > 0]
    iqr = (np.percentile(F, 90, axis=1) - np.percentile(F, 10, axis=1)).mean()
    print(f'{tag:<40} 均高{live.mean():5.1f}  极差{(F.max(1)-F.min(1)).mean():5.1f}  p90-p10{iqr:5.1f}  触顶{(F>=63).mean()*100:4.1f}%')

print('峰值保持衰减速度扫描（块率 44/s）')
for pd in [1,2,3,4,6]:
    show(f'  build① pk_decay={pd} ({pd*1024/FS*1000:.0f}px/s)', run(x, mode='band', smooth=True, pk_decay=pd))
print()
for pd in [1,2,3,4,6]:
    show(f'  C1 s6o48+A\' pk_decay={pd}', run(x, mode='glob', gslope=6, goff=48, gamma=LIN15, smooth=True, pk_decay=pd))
print()
for pd in [2,3,4]:
    show(f'  C1 s7o50+A\' pk_decay={pd}', run(x, mode='glob', gslope=7, goff=50, gamma=LIN15, smooth=True, pk_decay=pd))
    show(f'  C2 s6o48+A\' pk_decay={pd}', run(x, mode='hyb', gslope=6, goff=48, gamma=LIN15, smooth=True, pk_decay=pd))
