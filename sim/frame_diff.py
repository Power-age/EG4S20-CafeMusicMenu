import sys, glob, os
from PIL import Image, ImageChops
import numpy as np

d = sys.argv[1]
files = sorted(glob.glob(os.path.join(d, "f_*.png")))
print("frames", len(files))
prev = None
diffs = []
for i, f in enumerate(files):
    im = Image.open(f).convert("L").resize((160, 90))
    a = np.asarray(im, dtype=np.int16)
    if prev is not None:
        diffs.append((i, float(np.abs(a - prev).mean())))
    prev = a
big = [x for x in diffs if x[1] > 3.0]
print("diffs>3:", [(i, round(v, 1)) for i, v in big][:40])
