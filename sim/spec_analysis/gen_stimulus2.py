import numpy as np

FS = 48000
D = r"D:\AAA_University\Anlu\Project\sim\work_e15"

n1 = np.arange(int(FS * 0.30))
x1 = np.round(0.50 * 32767 * np.sin(2 * np.pi * 200 * n1 / FS))
n2 = np.arange(int(FS * 0.30))
x2 = (np.round(0.50 * 32767 * np.sin(2 * np.pi * 200 * n2 / FS))
      + np.round(0.30 * 32767 * np.sin(2 * np.pi * 3000 * n2 / FS)))
n3 = np.arange(int(FS * 0.20))
x3 = (np.round(0.50 * 32767 * np.sin(2 * np.pi * 200 * n3 / FS))
      + np.round(0.30 * 32767 * np.sin(2 * np.pi * 3000 * n3 / FS))
      + np.round(0.20 * 32767 * np.sin(2 * np.pi * 8000 * n3 / FS)))
x = np.concatenate([x1, x2, x3]).astype(np.int64)
assert np.abs(x).max() < 32767

path = D + r"\spec_stim2.mem"
with open(path, "w", encoding="ascii", newline="\n") as f:
    f.write("\n".join("%04X" % (v & 0xFFFF) for v in x) + "\n")
print("wrote", path, "n =", len(x), "peak =", round(np.abs(x).max() / 32767, 3))
