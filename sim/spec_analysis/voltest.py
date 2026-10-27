import numpy as np
from pathlib import Path
from calib2 import simulate, score
OUT = Path(r'D:\AAA_University\Anlu\Project\sim\spec_analysis')
F7 = np.load(OUT / 'fine_huoyuanjia.npy')
print('同一首歌，只改音量档（每档 6dB；vol=15 满，vol=1 = -23.5dB = 约 -16 个 1/4 倍频程单位）')
for tag, shift in [('vol=15', 0), ('vol=12', -4), ('vol=8', -8), ('vol=4', -12), ('vol=1', -16)]:
    F = np.clip(F7 + shift, 0, 127)
    score('  ' + tag, simulate(F, 54, 2, 0))
