import numpy as np
from pathlib import Path
from calib2 import simulate, score
OUT = Path(r'D:\AAA_University\Anlu\Project\sim\spec_analysis')
for tag, nm in [('huoyuanjia','霍元甲'), ('xiaobaima','小白马'), ('nailong','奶龙')]:
    F7 = np.load(OUT / ('fine_'+tag+'.npy'))
    print('===', nm)
    for em in (0, 4, 6, 8):
        score('  GOFF=54 GS=2 强调+%d' % em, simulate(F7, 54, 2, em))
