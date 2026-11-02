# -*- coding: utf-8 -*-
"""图2 系统总体框图 v3：正交折线布线，避免长斜线穿图。"""
import math
from PIL import Image, ImageDraw, ImageFont

OUT = r"D:\AAA_University\Anlu\Project\doc\报告\图2_系统总体框图.png"
F_B = r"C:\Windows\Fonts\msyhbd.ttc"
F_R = r"C:\Windows\Fonts\msyh.ttc"

W, H = 1800, 1120
INK = (30, 30, 30)
C_IMG = ((226, 238, 255), (52, 101, 164))
C_DIS = ((228, 245, 232), (46, 125, 79))
C_AUD = ((255, 241, 224), (186, 106, 24))
C_CTL = ((242, 234, 252), (106, 70, 160))
C_MEM = ((238, 238, 238), (105, 105, 105))


def font(sz, bold=False):
    return ImageFont.truetype(F_B if bold else F_R, sz)


def box(d, bb, colors, text, sz=19, bold=False):
    d.rounded_rectangle(bb, radius=10, fill=colors[0], outline=colors[1], width=2)
    f = font(sz, bold)
    t = d.multiline_textbbox((0, 0), text, font=f, spacing=3, align="center")
    tw, th = t[2] - t[0], t[3] - t[1]
    d.multiline_text(((bb[0] + bb[2] - tw) / 2 - t[0], (bb[1] + bb[3] - th) / 2 - t[1]),
                     text, font=f, fill=INK, spacing=3, align="center")


def poly_arrow(d, pts, color=(80, 80, 80), width=3, head=11):
    for i in range(len(pts) - 1):
        d.line([pts[i], pts[i + 1]], fill=color, width=width)
    p0, p1 = pts[-2], pts[-1]
    ang = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
    for s in (+1, -1):
        a = ang + s * 0.5
        d.line([p1, (p1[0] - head * math.cos(a), p1[1] - head * math.sin(a))], fill=color, width=width)


def lane(d, y, title, color, items, x0=330, w=196, gap=16, h=88, sz=18):
    d.text((x0, y - 30), title, font=font(21, True), fill=color[1])
    boxes, x = [], x0
    for t in items:
        b = (x, y, x + w, y + h)
        box(d, b, color, t, sz)
        boxes.append(b)
        x += w + gap
    for i in range(len(boxes) - 1):
        poly_arrow(d, [(boxes[i][2], y + h // 2), (boxes[i + 1][0], y + h // 2)])
    return boxes


img = Image.new("RGB", (W, H), (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((60, 24), "图 2  系统总体框图（单 FPGA、四通路）", font=font(32, True), fill=INK)

# 左列外设
tf = (60, 150, 270, 250);    box(d, tf, C_IMG, "TF 卡\nFAT32", 20, True)
sdr = (60, 360, 270, 500);   box(d, sdr, C_MEM, "板载 SDRAM\n2M×32bit\n四分区帧缓存", 19, True)
tf2 = (60, 580, 270, 670);   box(d, tf2, C_IMG, "TF 卡\n(FAT32)", 19, True)
key = (60, 790, 270, 890);   box(d, key, C_CTL, "按键 / 拨码\n4 键 + 4 位", 19, True)

# 右列输出
RX = W - 250
hdmi = (RX, 360, RX + 190, 500)
box(d, hdmi, C_MEM, "HDMI 1.4b\nTMDS 4 通道\n640×480@60", 19, True)
seg = (RX, 790, RX + 190, 890)
box(d, seg, C_CTL, "数码管 8 位\n图号/音量/状态", 18, True)

# 四条泳道
b1 = lane(d, 150, "① 图片通路（sd_card_clk 75MHz）", C_IMG,
          ["SD/SPI 控制器", "FAT32 根目录扫描", "簇链跟随\n(LBA 翻译)", "BMP 解码\n等比缩放"])
b2 = lane(d, 380, "② 显示通路（video_clk 25MHz，逐像素叠加）", C_DIS,
          ["帧读出\n帧边界切换", "亮度 / 对比度", "转场\nWIPE / FADE", "2× 商品放大",
           "中文角标\n1bit 掩膜", "OSD / 频谱柱"], w=176, gap=14)
b3 = lane(d, 600, "③ 音频通路（MCLK 12.288MHz，I2S 64fs）", C_AUD,
          ["PCM 流式播放\nBRAM 缓冲", "音量 / TONE\nQ15 增益", "I2S + ACR\n音画同步", "1024 点 DFT\n40 段频谱"])
b4 = lane(d, 800, "④ 控制通路（50MHz 基准）", C_CTL,
          ["按键消抖\n长短按/双击", "菜单控制器\n7 项参数", "翻页 / 切歌\n转场选择", "装载状态机\n扫描→装载→常驻"], w=186)

# ---------- 正交连线 ----------
# TF -> 图片首块
poly_arrow(d, [(tf[2], 200), (b1[0][0], 200)])
# 图片末块 -> 下 -> 左 -> SDRAM 顶部
x_mid = b1[-1][0] + 88
poly_arrow(d, [(x_mid, b1[-1][3]), (x_mid, 320), (165, 320), (165, sdr[1])])
d.text((x_mid + 10, 292), "异步 FIFO 写", font=font(15), fill=(90, 90, 90))
# SDRAM -> 显示首块
y_mid = 430
poly_arrow(d, [(sdr[2], y_mid), (b2[0][0], y_mid)])
d.text((sdr[2] + 8, 442), "异步 FIFO 读", font=font(15), fill=(90, 90, 90))
# 显示末块 -> HDMI
poly_arrow(d, [(b2[-1][2], y_mid), (hdmi[0], y_mid)])
# TF2 -> 音频首块
poly_arrow(d, [(tf2[2], 625), (b3[0][0], 625)])
# I2S(第3块) -> 下 -> 右 -> HDMI 底部
x3 = b3[2][0] + 88
poly_arrow(d, [(x3, b3[2][3]), (x3, 700), (RX + 95, 700), (RX + 95, hdmi[3])])
# DFT(第4块) -> 垂直上 -> OSD 底部
x4 = b3[3][0] + 98
x_osd = b2[5][0] + 88
poly_arrow(d, [(x4, b3[3][1]), (x4, 540), (x_osd, 540), (x_osd, b2[5][3])])
d.text((x4 + 10, 552), "幅度→柱高", font=font(15), fill=(90, 90, 90))
# 按键 -> 控制首块
poly_arrow(d, [(key[2], 840), (b4[0][0], 840)])
# 控制通路对外关系用文字标注（避免长绕线与 HDMI 处双箭头）
d.text((b4[1][0] - 6, b4[1][3] + 12), "菜单/参数 → OSD；翻页/切歌 → 帧边界提交", font=font(15), fill=(90, 90, 90))
# 装载状态机 -> 数码管
poly_arrow(d, [(b4[3][2], 840), (seg[0], 840)])

# ---------- 时钟域说明 ----------
cy = 960
d.rounded_rectangle((60, cy, W - 60, cy + 104), radius=12, outline=(180, 180, 180), width=2)
d.text((82, cy + 10), "时钟域与跨时钟域处理", font=font(20, True), fill=(60, 60, 60))
d.text((82, cy + 44),
       "50MHz 基准 → sys_pll：75MHz（SD 读）、125MHz（板载 SDRAM / HDMI 5×）；video_pll：25MHz（像素）；audio PLL：12.288MHz（MCLK）",
       font=font(17), fill=(70, 70, 70))
d.text((82, cy + 72),
       "跨域：多 bit 走异步 FIFO（双时钟 BRAM + 格雷码指针）；单 bit 控制两级同步；异步时钟对之间 set_clock_groups -asynchronous",
       font=font(17), fill=(70, 70, 70))

d.text((60, H - 34), "注：翻页、转场、参数变更均在帧消隐边界生效；显示链路逐像素叠加，无撕裂。",
       font=font(17), fill=(80, 80, 80))

img.save(OUT)
print("已生成:", OUT, img.size)
