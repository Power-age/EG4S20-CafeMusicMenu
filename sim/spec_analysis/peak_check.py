import numpy as np
from pathlib import Path

for n in ["TRACK01.RAW", "TRACK02.RAW", "TRACK03.RAW"]:
    a = np.fromfile(Path("F:/") / n, dtype="<i2")
    pk = int(np.abs(a.astype(np.int32)).max())
    print("%s: %d 样本 (%.1f s), 峰值 %d = %.2f dBFS"
          % (n, len(a), len(a) / 48000.0, pk, 20 * np.log10(pk / 32768.0)))
