import numpy as np

FS = 48000
TONES = [(200, .30), (900, .22), (3000, .12), (8000, .08)]
N_TONE = int(FS * 0.6)
N_SIL = int(FS * 1.0)
OUT = r"D:\AAA_University\Anlu\Project\sim\work_e15\spec_stim.mem"

n = np.arange(N_TONE)
x = np.zeros(N_TONE)
for f, a in TONES:
    x += a * 32767 * np.sin(2 * np.pi * f * n / FS)
x = np.round(x).astype(np.int64)
x = np.concatenate([x, np.zeros(N_SIL, dtype=np.int64)])
assert x.max() < 32767 and x.min() > -32768, (x.max(), x.min())
with open(OUT, "w", encoding="ascii", newline="\n") as f:
    f.write("\n".join("%04X" % (v & 0xFFFF) for v in x) + "\n")
np.save(OUT.replace(".mem", ".npy"), x)
print(f"wrote {OUT}  n={len(x)}  peak={np.abs(x).max()/32767:.3f}FS")
print("BIN(f/46.875): 200Hz->k%.1f  900Hz->k%.1f  3kHz->k%.1f  8kHz->k%.1f" %
      tuple(f / 46.875 for f, _ in TONES))
