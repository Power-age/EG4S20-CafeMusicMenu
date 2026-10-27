import struct
from pathlib import Path

for name in ["PIC1.bmp", "PIC3.bmp", "PIC4.bmp"]:
    p = Path(r"D:\AAA_University\Anlu\Project\doc\TF卡\bmp\好图") / name
    b = p.read_bytes()[:54]
    sig, size, r1, r2, off = struct.unpack("<2sIHHI", b[:14])
    hdrsize, w, h, planes, bpp = struct.unpack("<IiiHH", b[14:30])
    comp = struct.unpack("<I", b[30:34])[0]
    print("%s: %dx%d bpp=%d comp=%d off=%d hdr=%d file=%d"
          % (name, w, h, bpp, comp, off, hdrsize, p.stat().st_size))

print()
src = Path(r"D:\AAA_University\Anlu\Project\doc\TF卡\bmp\好图")
from PIL import Image

for name in sorted(src.glob("*-新.png")):
    im = Image.open(name)
    print("%s: %s %s" % (name.name, im.size, im.mode))
