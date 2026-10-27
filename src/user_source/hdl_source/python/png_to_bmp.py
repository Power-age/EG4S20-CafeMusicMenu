"""把新海报按"缩放适配演示矩阵"输出四种原生尺寸的 BMP。

顺序约定（按用户要求：小图/满屏图在前，超大图在后）：
  PIC1 640x480   原生直通，满屏，上电第一张
  PIC2 800x600   4:3 略缩，仍满屏
  PIC3 480x640   竖版放大 -> 左右黑边
  PIC4 1280x720  16:9 大图缩小 -> 上下黑边（降到 720p 以缩短上电时间）
"""
import struct
import sys
from pathlib import Path
from PIL import Image

SRC = Path(r"D:\AAA_University\Anlu\Project\doc\TF卡\bmp\好图")
DST = SRC / "转换后"

# (源图, 输出名, 目标尺寸)
PLAN = [
    ("PIC3-新.png", "PIC1.bmp", (640, 480)),    # 面包与咖啡：原生，满屏
    ("PIC4-新.png", "PIC2.bmp", (800, 600)),    # 打烊夜景：4:3 略缩，满屏
    ("PIC2-新.png", "PIC3.bmp", (480, 640)),    # 黑白照片墙：竖版放大，左右黑边
    ("PIC1-新.png", "PIC4.bmp", (1280, 720)),   # 晨光吧台：16:9 大图缩小，上下黑边
]


def crop_to_ratio(im, ratio):
    w, h = im.size
    if w / h > ratio:
        nw = int(round(h * ratio))
        x0 = (w - nw) // 2
        return im.crop((x0, 0, x0 + nw, h))
    nh = int(round(w / ratio))
    y0 = (h - nh) // 2
    return im.crop((0, y0, w, y0 + nh))


def info(p):
    b = p.read_bytes()[:54]
    hdrsize, w, h, planes, bpp = struct.unpack("<IiiHH", b[14:30])
    comp = struct.unpack("<I", b[30:34])[0]
    return w, h, bpp, comp


def main():
    DST.mkdir(exist_ok=True)
    ok, total = True, 0
    for src_name, out_name, size in PLAN:
        src = SRC / src_name
        if not src.exists():
            print("缺少源图:", src)
            ok = False
            continue
        im = Image.open(src).convert("RGB")
        sw, sh = im.size
        ratio = size[0] / size[1]
        im = crop_to_ratio(im, ratio).resize(size, Image.LANCZOS)
        dst = DST / out_name
        im.save(dst, format="BMP")
        w, h, bpp, comp = info(dst)
        total += dst.stat().st_size
        # 上屏后的行为预估
        if abs(size[0] / size[1] - 640 / 480) < 0.01:
            behave = "满屏（同 4:3，等比缩放）"
        elif size[0] / size[1] > 640 / 480:
            behave = "缩小 + 上下黑边"
        else:
            behave = "放大 + 左右黑边"
        print("%-9s <- %-12s 源 %4dx%-4d -> %4dx%-4d  %.2f MB  %s"
              % (out_name, src_name, sw, sh, w, h, dst.stat().st_size / 1e6, behave))
        if (w, h) != size or bpp != 24 or comp != 0:
            print("  !! 格式不符预期")
            ok = False
    print("\n四张合计 %.2f MB" % (total / 1e6))
    print("全部通过" if ok else "存在问题")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
