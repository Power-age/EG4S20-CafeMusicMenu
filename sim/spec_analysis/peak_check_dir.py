import sys
from pathlib import Path
import numpy as np

d = Path(sys.argv[1] if len(sys.argv) > 1 else r"D:\AAA_University\Anlu\Project\doc\TF卡\raw_new")
for n in sorted(d.glob("TRACK*.RAW")):
    a = np.fromfile(n, dtype="<i2")
    pk = int(np.abs(a.astype(np.int32)).max())
    print("  %s: %d 样本 (%.1f s)  峰值 %d = %.2f dBFS"
          % (n.name, len(a), len(a) / 48000.0, pk, 20 * np.log10(pk / 32768.0)))
