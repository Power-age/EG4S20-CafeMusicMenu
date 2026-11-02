# -*- coding: utf-8 -*-
"""图2 重排（四泳道，每条自带左侧源框，标签不与框重叠）+ 其余图字号加大。"""
import math
from PIL import Image, ImageDraw, ImageFont

OUT = r"D:\AAA_University\Anlu\Project\doc\报告"
F_B = r"C:\Windows\Fonts\msyhbd.ttc"
F_R = r"C:\Windows\Fonts\msyh.ttc"
INK = (0, 0, 0)
GRAY = (105, 105, 105)


def font(sz, bold=False):
    return ImageFont.truetype(F_B if bold else F_R, sz)


def rect(d, bb, text, sz=28, bold=False, lw=2):
    d.rectangle(bb, outline=INK, width=lw, fill=(255, 255, 255))
    f = font(sz, bold)
    t = d.multiline_textbbox((0, 0), text, font=f, spacing=6, align="center")
    tw, th = t[2] - t[0], t[3] - t[1]
    d.multiline_text(((bb[0] + bb[2] - tw) / 2 - t[0], (bb[1] + bb[3] - th) / 2 - t[1]),
                     text, font=f, fill=INK, spacing=6, align="center")


def arrow(d, pts, lw=2, head=12):
    for i in range(len(pts) - 1):
        d.line([pts[i], pts[i + 1]], fill=INK, width=lw)
    p0, p1 = pts[-2], pts[-1]
    ang = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
    for s in (+1, -1):
        a = ang + s * 0.42
        d.line([p1, (p1[0] - head * math.cos(a), p1[1] - head * math.sin(a))], fill=INK, width=lw)


def label(d, x, y, text):
    d.text((x, y), text, font=font(24, True), fill=GRAY)


# ================= 图2 系统总体框图（四泳道） =================
W, H = 1320, 880
img = Image.new("RGB", (W, H), (255, 255, 255))
d = ImageDraw.Draw(img)

BH = 92                       # 统一框高

# ---- 泳道1 图片通路 ----
label(d, 30, 26, "① 图片通路  75MHz")
tf = (30, 70, 220, 70 + BH)
rect(d, tf, "TF 卡\n(FAT32)", 26, True)
x = 280
b1 = []
for t in ["SD/SPI 控制器", "FAT32 根目录扫描", "BMP 解码\n等比缩放"]:
    b = (x, 70, x + 250, 70 + BH)
    rect(d, b, t, 24)
    b1.append(b)
    x += 280
arrow(d, [(tf[2], 70 + BH // 2), (b1[0][0], 70 + BH // 2)])
for i in range(len(b1) - 1):
    arrow(d, [(b1[i][2], 70 + BH // 2), (b1[i + 1][0], 70 + BH // 2)])

# ---- 泳道2 显示通路 ----
label(d, 30, 196, "② 显示通路  25MHz 像素时钟")
sdr = (30, 240, 220, 240 + BH)
rect(d, sdr, "板载 SDRAM\n四分区帧缓存", 24, True)
# 图片通路 -> SDRAM（右侧下行，短折线）
arrow(d, [(b1[-1][0] + 125, b1[-1][3]), (b1[-1][0] + 125, 216), (125, 216), (125, sdr[1])])
d.text((b1[-1][0] + 133, 220), "异步 FIFO 写", font=font(20), fill=GRAY)

b2 = (280, 240, 700, 240 + BH)
rect(d, b2, "逐像素叠加\n亮度/对比度 · 转场 · 2× 放大 · 中文字幕", 22)
arrow(d, [(sdr[2], 240 + BH // 2), (b2[0], 240 + BH // 2)])
hd = (1000, 240, 1290, 240 + BH)
rect(d, hd, "HDMI 1.4b\n640×480@60", 24, True)
arrow(d, [(b2[2], 240 + BH // 2), (hd[0], 240 + BH // 2)])

# ---- 泳道3 音频通路 ----
label(d, 30, 376, "③ 音频通路  12.288MHz MCLK")
tf2 = (30, 420, 220, 420 + BH)
rect(d, tf2, "TF 卡\n(PCM)", 26, True)
x = 280
b3 = []
for t in ["PCM 流式播放\nBRAM 缓冲", "音量 / TONE", "I2S + ACR", "1024 点 DFT\n40 段频谱"]:
    b = (x, 420, x + 226, 420 + BH)
    rect(d, b, t, 22)
    b3.append(b)
    x += 252
arrow(d, [(tf2[2], 420 + BH // 2), (b3[0][0], 420 + BH // 2)])
for i in range(len(b3) - 1):
    arrow(d, [(b3[i][2], 420 + BH // 2), (b3[i + 1][0], 420 + BH // 2)])
# 音频 -> HDMI（右侧上行，走最右空白列）
arrow(d, [(b3[2][0] + 113, b3[2][1]), (b3[2][0] + 113, 392), (1205, 392), (1205, hd[3])])
d.text((b3[2][0] + 121, 366), "→ HDMI 音频", font=font(20), fill=GRAY)
# DFT -> 叠加框（竖直短箭头）
arrow(d, [(b3[3][0] + 113, b3[3][1]), (b3[3][0] + 113, 356), (b2[0] + 210, 356), (b2[0] + 210, b2[3])])
d.text((b3[3][0] + 121, 330), "频谱叠加", font=font(20), fill=GRAY)

# ---- 泳道4 控制通路 ----
label(d, 30, 556, "④ 控制通路  50MHz 基准")
kbd = (30, 600, 220, 600 + BH)
rect(d, kbd, "按键 / 拨码", 26, True)
x = 280
b4 = []
for t in ["按键消抖\n长短按/双击", "菜单控制器\n7 项参数", "翻页 / 切歌\n转场选择"]:
    b = (x, 600, x + 226, 600 + BH)
    rect(d, b, t, 22)
    b4.append(b)
    x += 252
arrow(d, [(kbd[2], 600 + BH // 2), (b4[0][0], 600 + BH // 2)])
for i in range(len(b4) - 1):
    arrow(d, [(b4[i][2], 600 + BH // 2), (b4[i + 1][0], 600 + BH // 2)])
# 翻页 -> 叠加框（竖直向上短箭头）
arrow(d, [(b4[2][0] + 113, b4[2][1]), (b4[2][0] + 113, 536), (b2[0] + 420, 536), (b2[0] + 420, b2[3])])
d.text((b4[2][0] + 121, 510), "切页/参数", font=font(20), fill=GRAY)
# 状态 -> 数码管
seg = (1000, 600, 1290, 600 + BH)
rect(d, seg, "数码管 8 位\n图号/音量/状态", 24, True)
arrow(d, [(b4[2][2], 600 + BH // 2), (seg[0], 600 + BH // 2)])

d.text((30, H - 60), "注：跨时钟域数据经异步 FIFO，单 bit 控制两级同步；所有切换在帧消隐边界生效。",
       font=font(22), fill=GRAY)
img.save(OUT + r"\图2_系统总体框图.png")

# ================= 图9 叠加管线（字号加大） =================
W, H = 1320, 260
img = Image.new("RGB", (W, H), (255, 255, 255))
d = ImageDraw.Draw(img)
items = ["帧读出", "亮度/对比度", "转场", "2× 放大", "中文角标", "OSD/频谱", "AXIS"]
x = 30
bs = []
for t in items:
    b = (x, 60, x + 168, 150)
    rect(d, b, t, 26)
    bs.append(b)
    x += 186
for i in range(len(bs) - 1):
    arrow(d, [(bs[i][2], 105), (bs[i + 1][0], 105)])
d.text((30, 190), "25MHz 逐拍叠加；翻页与转场在帧消隐边界提交", font=font(22), fill=GRAY)
img.save(OUT + r"\图9_叠加管线.png")

# ================= 图10 频谱流程（字号加大） =================
W, H = 1320, 380
img = Image.new("RGB", (W, H), (255, 255, 255))
d = ImageDraw.Draw(img)
items = ["增益后 PCM", "取 1024 点", "Q15 定点 DFT", "|I| + |Q|", "对数分 40 段"]
x = 30
bs = []
for t in items:
    b = (x, 70, x + 236, 160)
    rect(d, b, t, 26)
    bs.append(b)
    x += 254
for i in range(len(bs) - 1):
    arrow(d, [(bs[i][2], 115), (bs[i + 1][0], 115)])
b6 = (30, 240, 500, 330)
rect(d, b6, "平滑 + 峰值保持", 26)
b7 = (560, 240, 1030, 330)
rect(d, b7, "渲染为最底行 40 段柱", 26)
arrow(d, [(bs[2][0] + 118, bs[2][3]), (bs[2][0] + 118, 200), (b6[0] + 235, 200), (b6[0] + 235, b6[1])])
arrow(d, [(b6[2], 285), (b7[0], 285)])
d.text((30, 348), "每 42 帧刷新；无 AGC，固定参考映射", font=font(22), fill=GRAY)
img.save(OUT + r"\图10_频谱流程.png")

print("图2 重排完成；图9/图10 字号加大")
