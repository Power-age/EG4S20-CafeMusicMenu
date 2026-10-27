"""把中文文案渲染成 512x32 的 2bit 灰度 mask（4 档 alpha），输出 SUB1.BIN~SUB4.BIN。

格式（与 FPGA 侧约定）：
  每像素 2bit，行优先，每字节 4 个像素，字节内从左到右依次占 bit[1:0] [3:2] [5:4] [7:6]；
  每行 512/4 = 128 字节，共 32 行 -> 每条 4096 字节；4 条共 16KB。
  取值：0 = 无文字（显示底带），1~3 = alpha 由弱到强（3 = 完全不透明文字色）。

换文案只需改 CAPTIONS，然后重跑本脚本并把 BIN 拷到 TF 卡根目录。
"""
import io
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT = Path(r"D:\AAA_University\Anlu\Project\doc\TF卡\sub_mask")
W, H = 512, 32
CAPTIONS = [
    "咖啡与奶香 · 今日推荐",
    "面包房现烤 · 每日新鲜",
    "抹茶与甜品 · 下午时光",
    "冰饮与麦芬 · 清凉一夏",
]
FONT_CANDIDATES = [
    r"C:\Windows\Fonts\msyh.ttc",      # 微软雅黑
    r"C:\Windows\Fonts\msyhbd.ttc",
    r"C:\Windows\Fonts\simhei.ttf",    # 黑体
    r"C:\Windows\Fonts\simsun.ttc",
]
SIZE = 24


def pick_font():
    for f in FONT_CANDIDATES:
        if Path(f).exists():
            return f
    raise FileNotFoundError("找不到中文字体")


def render(text, font_path):
    # 先渲染到灰度图，再量化成 4 档
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(font_path, SIZE)
    bbox = d.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    x = (W - tw) // 2 - bbox[0]
    y = (H - th) // 2 - bbox[1]
    d.text((x, y), text, fill=255, font=font)
    # 4 档量化：0 / 85 / 170 / 255 -> 0 / 1 / 2 / 3
    px = img.load()
    q = Image.new("L", (W, H), 0)
    qp = q.load()
    for yy in range(H):
        for xx in range(W):
            v = px[xx, yy]
            qp[xx, yy] = 0 if v < 40 else (1 if v < 120 else (2 if v < 210 else 3))
    return q


def pack(q):
    buf = bytearray(W // 4 * H)
    qp = q.load()
    i = 0
    for yy in range(H):
        for xx in range(0, W, 4):
            b = 0
            for k in range(4):
                b |= (qp[xx + k, yy] & 3) << (2 * k)
            buf[i] = b
            i += 1
    return bytes(buf)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    fp = pick_font()
    print("字体:", fp, " 字号:", SIZE)
    for i, text in enumerate(CAPTIONS, start=1):
        q = render(text, fp)
        data = pack(q)
        dst = OUT / ("SUB%d.BIN" % i)
        dst.write_bytes(data)
        nz = sum(1 for b in data if b)
        print("  SUB%d.BIN  %d 字节  非零字节 %d  %s" % (i, len(data), nz, text))
    print("\n输出目录:", OUT)


if __name__ == "__main__":
    main()
