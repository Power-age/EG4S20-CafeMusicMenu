# -*- coding: utf-8 -*-
"""绘制《技术报告》系统总体框图（图2）—— 四通路版，贴合当前实现。"""
import os
from PIL import Image, ImageDraw, ImageFont

OUT = r"D:\AAA_University\Anlu\Project\doc\报告\图2_系统总体框图.png"
F_B = r"C:\Windows\Fonts\msyhbd.ttc"
F_R = r"C:\Windows\Fonts\msyh.ttc"

W, H = 1800, 1020
BG = (255, 255, 255)
INK = (34, 34, 34)
BLUE = (232, 240, 254)      # 图片通路
BLUE_E = (66, 110, 180)
GREEN = (233, 246, 235)     # 显示通路
GREEN_E = (56, 132, 86)
ORANGE = (255, 244, 230)    # 音频通路
ORANGE_E = (200, 120, 40)
PURPLE = (243, 236, 250)    # 控制通路
PURPLE_E = (122, 86, 170)
GRAY = (245, 245, 245)
GRAY_E = (150, 150, 150)


def font(size, bold=False):
    return ImageFont.truetype(F_B if bold else F_R, size)


def rounded(d, box, fill, edge, width=2, r=10):
    d.rounded_rectangle(box, radius=r, fill=fill, outline=edge, width=width)


def ctext(d, box, text, f, fill=INK):
    x0, y0, x1, y1 = box
    bb = d.multiline_textbbox((0, 0), text, font=f, spacing=4, align="center")
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    d.multiline_text(((x0 + x1 - tw) / 2 - bb[0], (y0 + y1 - th) / 2 - bb[1]),
                     text, font=f, fill=fill, spacing=4, align="center")


def arrow(d, p0, p1, color=(90, 90, 90), width=3, head=12):
    d.line([p0, p1], fill=color, width=width)
    import math
    ang = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
    for s in (+1, -1):
        a = ang + s * 0.45
        d.line([p1, (p1[0] - head * math.cos(a), p1[1] - head * math.sin(a))], fill=color, width=width)


img = Image.new("RGB", (W, H), BG)
d = ImageDraw.Draw(img)

# ---------- 标题 ----------
ctext(d, (0, 18, W, 70), "图 2  系统总体框图（单 FPGA、四通路）", font(34, True))

# ---------- 片内大框 ----------
FPGA_BOX = (60, 92, W - 60, H - 60)
d.rounded_rectangle(FPGA_BOX, radius=18, outline=(90, 90, 90), width=3)
d.text((FPGA_BOX[0] + 16, FPGA_BOX[1] + 10), "安路 EG4S20BG256 片内逻辑", font=font(22, True), fill=(60, 60, 60))

# ---------- 板载外设（框外顶部）----------
peri = [("TF 卡\n(FAT32)", 120), ("板载 SDRAM\n2M×32bit", 380), ("QSPI Flash\n(固化)", 690),
        ("HDMI 接口\n(TMDS)", 980), ("按键 / 拨码", 1260), ("数码管\n8 位", 1520)]
box_w, box_h, y0 = 190, 66, 20
per_boxes = {}
for name, x in peri:
    b = (x, y0, x + box_w, y0 + box_h)
    rounded(d, b, GRAY, GRAY_E)
    ctext(d, b, name, font(19))
    per_boxes[name.split("\n")[0]] = b

# ---------- 通路 1：图片 ----------
lane1_y = 150
d.text((80, lane1_y - 34), "① 图片通路（sd_card_clk 75MHz）", font=font(21, True), fill=BLUE_E)
imgs = ["SD/SPI\n控制器", "FAT32\n根目录扫描", "簇链跟随\n(LBA 翻译)", "BMP 解码\n等比缩放"]
x = 100
img_boxes = []
for t in imgs:
    b = (x, lane1_y, x + 210, lane1_y + 84)
    rounded(d, b, BLUE, BLUE_E)
    ctext(d, b, t, font(19))
    img_boxes.append(b)
    x += 250
# TF 卡 -> 第一个
arrow(d, (per_boxes["TF 卡"][0] + 95, per_boxes["TF 卡"][3]), (img_boxes[0][0] + 105, lane1_y))
for i in range(len(img_boxes) - 1):
    arrow(d, (img_boxes[i][2], lane1_y + 42), (img_boxes[i + 1][0], lane1_y + 42))
# 缩放 -> SDRAM
sdr = per_boxes["板载 SDRAM"]
arrow(d, (img_boxes[-1][0] + 105, img_boxes[-1][3]), (sdr[0] + 95, sdr[3]))
d.text((img_boxes[-1][0] + 118, img_boxes[-1][3] + 8), "异步 FIFO", font=font(16), fill=(90, 90, 90))

# ---------- 通路 2：显示 ----------
lane2_y = 330
d.text((80, lane2_y - 34), "② 显示通路（video_clk 25MHz 逐像素叠加）", font=font(21, True), fill=GREEN_E)
disps = ["视频时序\n640×480@60", "帧读出\n(帧边界切换)", "亮度/对比度", "转场\nWIPE / FADE",
         "2× 商品放大", "中文角标\n(1bit 掩膜)", "OSD / 频谱柱"]
x = 100
disp_boxes = []
for t in disps:
    b = (x, lane2_y, x + 196, lane2_y + 84)
    rounded(d, b, GREEN, GREEN_E)
    ctext(d, b, t, font(18))
    disp_boxes.append(b)
    x += 232
for i in range(len(disp_boxes) - 1):
    arrow(d, (disp_boxes[i][2], lane2_y + 42), (disp_boxes[i + 1][0], lane2_y + 42))
# SDRAM -> 帧读出
arrow(d, (sdr[0] + 95, sdr[3]), (disp_boxes[1][0] + 98, lane2_y))
d.text((disp_boxes[1][0] - 60, lane2_y - 26), "读经异步 FIFO", font=font(15), fill=(90, 90, 90))
# 末尾 -> HDMI
hd = per_boxes["HDMI 接口"]
arrow(d, (disp_boxes[-1][0] + 98, disp_boxes[-1][3]), (hd[0] + 95, hd[3]))

# ---------- 通路 3：音频 ----------
lane3_y = 510
d.text((80, lane3_y - 34), "③ 音频通路（12.288MHz MCLK / I2S 64fs）", font=font(21, True), fill=ORANGE_E)
auds = ["PCM 流式播放\n(BRAM 缓冲)", "簇索引\n±10s 快进快退", "音量 / TONE\n(Q15 增益)", "I2S + ACR\n音画同步", "1024 点 DFT\n40 段频谱"]
x = 100
aud_boxes = []
for t in auds:
    w = 240 if "DFT" in t else 220
    b = (x, lane3_y, x + w, lane3_y + 84)
    rounded(d, b, ORANGE, ORANGE_E)
    ctext(d, b, t, font(18))
    aud_boxes.append(b)
    x += w + 30
for i in range(len(aud_boxes) - 1):
    arrow(d, (aud_boxes[i][2], lane3_y + 42), (aud_boxes[i + 1][0], lane3_y + 42))
arrow(d, (sdr[0] + 20, sdr[3] + 0), (per_boxes["TF 卡"][0] + 40, sdr[3]), color=(255, 255, 255), width=0)
arrow(d, (per_boxes["TF 卡"][0] + 40, per_boxes["TF 卡"][3]), (aud_boxes[0][0] + 110, lane3_y))
arrow(d, (aud_boxes[3][0] + 110, aud_boxes[3][3]), (hd[0] + 60, hd[3]))
# DFT -> 频谱柱（接到显示通路倒数第一个）
arrow(d, (aud_boxes[4][0] + 120, lane3_y), (disp_boxes[-1][0] + 98, disp_boxes[-1][3]))

# ---------- 通路 4：控制 ----------
lane4_y = 690
d.text((80, lane4_y - 34), "④ 控制通路（50MHz 基准时钟）", font=font(21, True), fill=PURPLE_E)
ctrls = ["按键消抖\n长短按/双击", "拨码开关\n模式选择", "菜单控制器\n7 项参数", "翻页/切歌\n转场模式", "数码管扫描\n状态显示"]
x = 100
c_boxes = []
for t in ctrls:
    b = (x, lane4_y, x + 226, lane4_y + 84)
    rounded(d, b, PURPLE, PURPLE_E)
    ctext(d, b, t, font(18))
    c_boxes.append(b)
    x += 262
for i in range(len(c_boxes) - 1):
    arrow(d, (c_boxes[i][2], lane4_y + 42), (c_boxes[i + 1][0], lane4_y + 42))
arrow(d, (per_boxes["按键 / 拨码"][0] + 95, per_boxes["按键 / 拨码"][3]), (c_boxes[0][0] + 113, lane4_y))
arrow(d, (c_boxes[4][0] + 113, c_boxes[4][3]), (per_boxes["数码管"][0] + 95, per_boxes["数码管"][3]))
# 菜单控制器 -> OSD
arrow(d, (c_boxes[2][0] + 113, lane4_y), (disp_boxes[-1][0] + 30, disp_boxes[-1][3]))

# ---------- 图例 ----------
leg_y = H - 52
d.rectangle((100, leg_y, 126, leg_y + 22), fill=BLUE, outline=BLUE_E, width=2)
d.text((134, leg_y - 2), "图片", font=font(17), fill=INK)
d.rectangle((210, leg_y, 236, leg_y + 22), fill=GREEN, outline=GREEN_E, width=2)
d.text((244, leg_y - 2), "显示", font=font(17), fill=INK)
d.rectangle((320, leg_y, 346, leg_y + 22), fill=ORANGE, outline=ORANGE_E, width=2)
d.text((354, leg_y - 2), "音频", font=font(17), fill=INK)
d.rectangle((430, leg_y, 456, leg_y + 22), fill=PURPLE, outline=PURPLE_E, width=2)
d.text((464, leg_y - 2), "控制", font=font(17), fill=INK)
d.text((560, leg_y - 2), "注：跨时钟域数据经异步 FIFO，单 bit 控制经两级同步；所有切换在帧消隐边界生效。",
       font=font(17), fill=(80, 80, 80))

img.save(OUT)
print("已生成:", OUT, img.size)
