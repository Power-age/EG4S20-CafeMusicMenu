"""高质量掩膜文字渲染器（1bit + 抖动抗锯齿）。

原理：4x 超采样渲染 → 覆盖率 0~255 → 用 4x4 Bayer 阈值量化成 1bit，
      视觉上等效灰度抗锯齿；再做孤立点清除。
直接输出：
  - 预览 PNG（1x 与 4x 放大，便于人眼比对）
  - 指定尺寸的 1bit 位图（供打包进 MIF）

用法示例见文件末尾 __main__。
"""
from PIL import Image, ImageDraw, ImageFont

CN_BOLD = r"C:\Windows\Fonts\msyhbd.ttc"
CN_REG = r"C:\Windows\Fonts\msyh.ttc"
EN_BOLD = r"C:\Windows\Fonts\msyhbd.ttc"

BAYER4 = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]


def render_coverage(items, w, h, ss=4):
    """items: [(text, font_path, size_px, x, y)]，坐标按目标尺寸计。
    返回 'L' 模式覆盖率图（0..255），尺寸 w x h。"""
    big = Image.new("L", (w * ss, h * ss), 0)
    d = ImageDraw.Draw(big)
    for text, fpath, size, x, y in items:
        f = ImageFont.truetype(fpath, size * ss)
        d.text((x * ss, y * ss), text, font=f, fill=255)
    return big.resize((w, h), Image.BOX)


def despeckle(bits, w, h):
    """去掉孤立的单像素点（8 邻域内没有邻居的点）。"""
    out = bits[:]
    for y in range(h):
        for x in range(w):
            if not out[y * w + x]:
                continue
            n = 0
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    if dx == 0 and dy == 0:
                        continue
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < h and 0 <= xx < w and bits[yy * w + xx]:
                        n += 1
            if n == 0:
                out[y * w + x] = 0
    return out


def to_bits(cov, w, h, mode="edge"):
    """覆盖率 → 1bit。
    mode="hard" —— 纯 0.5 阈值（旧做法，硬边）
    mode="full" —— 全抖动（小字会发沙，不推荐）
    mode="edge" —— 【推荐】内核实心 + 只在边缘带抖动
    """
    CORE = 0.62      # 覆盖率高于此值 → 实心
    GONE = 0.18      # 低于此值 → 完全丢弃
    px = cov.load()
    bits = [0] * (w * h)
    for y in range(h):
        for x in range(w):
            c = px[x, y] / 255.0
            if c <= GONE:
                continue
            if mode == "hard":
                bits[y * w + x] = 1 if c > 0.5 else 0
            elif mode == "full":
                thr = (BAYER4[y % 4][x % 4] + 0.5) / 16.0
                bits[y * w + x] = 1 if c > thr else 0
            else:  # edge
                if c >= CORE:
                    bits[y * w + x] = 1
                else:
                    # 边缘带：按覆盖率重映射到 0..1 再做抖动
                    t = (c - GONE) / (CORE - GONE)
                    thr = (BAYER4[y % 4][x % 4] + 0.5) / 16.0
                    bits[y * w + x] = 1 if t > thr else 0
    return bits


def bits_to_image(bits, w, h, fg=255, bg=0):
    img = Image.new("L", (w, h), bg)
    p = img.load()
    for y in range(h):
        for x in range(w):
            if bits[y * w + x]:
                p[x, y] = fg
    return img


if __name__ == "__main__":
    W, H = 200, 80
    items = [
        ("抹茶拿铁", CN_BOLD, 34, 6, 2),
        ("宇治抹茶", CN_REG, 15, 8, 42),
        ("微苦回甘", CN_REG, 15, 8, 60),
        ("¥30", CN_BOLD, 26, 138, 46),
    ]
    cov = render_coverage(items, W, H, ss=4)

    out = Image.new("L", (W * 3 + 24, H + 8), 40)
    out.paste(bits_to_image(to_bits(cov, W, H, "hard"), W, H), (0, 4))
    out.paste(bits_to_image(to_bits(cov, W, H, "full"), W, H), (W + 12, 4))
    out.paste(bits_to_image(despeckle(to_bits(cov, W, H, "edge"), W, H), W, H), (2 * W + 24, 4))

    out.resize(((W * 3 + 24) * 4, (H + 8) * 4), Image.NEAREST).save(
        r"D:\AAA_University\Anlu\Project\sim\diag_covers\text_quality_cmp.png")
    print("预览: sim/diag_covers/text_quality_cmp.png")
    print("左=纯阈值(旧)  中=全抖动(太沙)  右=边缘抖动(推荐)")
