"""生成 4 页中文角标的 1bit 掩膜 MIF（4096 x 32bit）。

布局与 mask_overlay.v 一致：
  addr = page[1:0] * 1024 + block * 512 + word[8:0]
  block 0 = 左窗口 (200x80)，block 1 = 右窗口（本用途为空）
  窗口内线性像素索引 p = ly*200 + lx；word = p>>5，bit = p&31（LSB 优先）
"""
import io
import numpy as np
from PIL import Image, ImageDraw, ImageFont

OUT = r"D:\AAA_University\Anlu\Project\src\user_source\hdl_source\txt_all.mif"
FONT = r"C:\Windows\Fonts\msyhbd.ttc"

TEXTS = ["每日现磨", "今日推荐", "经典之选", "人气单品"]
WIN_W, WIN_H = 200, 80
BADGE_W, BADGE_H = 118, 26
BADGE_X, BADGE_Y = 2, 1          # 在窗口内的位置（窗口左上角贴齐角标区）

BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32)


def to_1bit(cov, core=0.62, gone=0.18):
    h, w = cov.shape
    thr = np.tile(BAYER4, (h // 4 + 1, w // 4 + 1))[:h, :w]
    thr = (thr + 0.5) / 16.0
    t = np.clip((cov - gone) / (core - gone), 0, 1)
    return np.where(cov >= core, 1.0, np.where(cov <= gone, 0.0, (t > thr).astype(np.float32)))


def render(text):
    ss = 4
    big = Image.new("L", (BADGE_W * ss, BADGE_H * ss), 0)
    f = ImageFont.truetype(FONT, 24 * ss)
    d = ImageDraw.Draw(big)
    tw = d.textlength(text, font=f)
    x = (BADGE_W * ss - tw) / 2
    bbox = d.textbbox((0, 0), text, font=f)          # 垂直居中：按实际字形高度对齐
    th = bbox[3] - bbox[1]
    y = (BADGE_H * ss - th) / 2 - bbox[1]
    d.text((x, y), text, font=f, fill=255)
    cov = np.asarray(big.resize((BADGE_W, BADGE_H), Image.BOX)).astype(np.float32) / 255.0
    return to_1bit(cov)


def window_bits(page):
    """把该页角标放到 200x80 窗口里，返回 16000 个 bit（0/1）。"""
    win = np.zeros((WIN_H, WIN_W), dtype=np.uint8)
    b = render(TEXTS[page])
    win[BADGE_Y:BADGE_Y + BADGE_H, BADGE_X:BADGE_X + BADGE_W] = (b > 0.5).astype(np.uint8)
    return win.reshape(-1)


def main():
    words = np.zeros(4096, dtype=np.uint32)
    for page in range(4):
        bits = window_bits(page)
        assert bits.size <= 512 * 32, bits.size
        for w in range(512):
            chunk = bits[w * 32:(w + 1) * 32]
            v = 0
            for i, b in enumerate(chunk):
                if b:
                    v |= (1 << i)
            words[page * 1024 + 0 * 512 + w] = v
    # 右窗口保持全零

    lines = ["WIDTH=32;", "DEPTH=4096;", "", "ADDRESS_RADIX=HEX;", "DATA_RADIX=HEX;", "", "CONTENT BEGIN"]
    for i, v in enumerate(words):
        lines.append("%04X : %08X;" % (i, int(v)))
    lines.append("END;")
    io.open(OUT, "w", encoding="ascii", newline="\n").write("\n".join(lines) + "\n")
    nz = int((words != 0).sum())
    print("MIF 已生成:", OUT)
    print("非零字数:", nz, " / 4096")
    for page in range(4):
        bits = window_bits(page)
        print("  page%d 文字像素: %d" % (page, int(bits.sum())))


if __name__ == "__main__":
    main()
