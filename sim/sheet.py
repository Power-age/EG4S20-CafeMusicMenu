import sys, glob, os
from PIL import Image

d = sys.argv[1]
sel = sys.argv[2] if len(sys.argv) > 2 else ""
files = sorted(glob.glob(os.path.join(d, "f_*.png")))
if sel:
    idx = [int(x) for x in sel.split(",")]
    pick = [files[i] for i in idx if 0 <= i < len(files)]
else:
    pick = files[::6][:8]
tw, th = 480, 270
cols = 4
rows = max(1, (len(pick) + cols - 1) // cols)
sheet = Image.new("RGB", (tw * cols, th * rows), (20, 20, 20))
for i, f in enumerate(pick):
    im = Image.open(f)
    w, h = im.size
    box = (int(0.052 * w), int(0.037 * h), int(0.896 * w), int(0.926 * h))
    im = im.crop(box).resize((tw, th), Image.LANCZOS)
    sheet.paste(im, ((i % cols) * tw, (i // cols) * th))
out = os.path.join(d, "sheet.png")
sheet.save(out)
print(out)
print("picked", [os.path.basename(p) for p in pick])
