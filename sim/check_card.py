from PIL import Image
import os
for n in range(1, 5):
    p = "E:/PIC%d.BMP" % n
    im = Image.open(p)
    print("PIC%d.BMP %s %s %d bytes" % (n, im.size, im.mode, os.path.getsize(p)))
for f in ("TRACK01.RAW", "TRACK02.RAW", "TRACK03.RAW"):
    p = "E:/" + f
    sz = os.path.getsize(p)
    print("%s %d bytes  %.1f s @48k/16bit" % (f, sz, sz / 96000.0))
