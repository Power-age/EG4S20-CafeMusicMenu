# -*- coding: utf-8 -*-
"""图2 系统总体框图 v2：左外设列 + 四条泳道 + 右输出列，连线只走相邻块。"""
import math
from PIL import Image, ImageDraw, ImageFont

OUT = r"D:\AAA_University\Anlu\Project\doc\报告\图2_系统总体框图.png"
F_B = r"C:\Windows\Fonts\msyhbd.ttc"
F_R = r"C:\Windows\Fonts\msyh.ttc"

W, H = 1800, 1080
BG = (255, 255, 255)
INK = (30, 30, 30)
C_IMG = ((226, 238, 255), (52, 101, 164))
C_DIS = ((228, 245, 232), (46, 125, 79))
C_AUD = ((255, 241, 224), (186, 106, 24))
C_CTL = ((242, 234, 252), (106, 70, 160))
C_OUT = ((236, 236, 236), (110, 110, 110))


def font(sz, bold=False):
    return ImageFont.truetype(F_B if bold else F_R, sz)


def box(d, bb, colors, text, sz=19, bold=False):
    d.rounded_rectangle(bb, radius=10, fill=colors[0], outline=colors[1], width=2)
    f = font(sz, bold)
    t = d.multiline_textbbox((0, 0), text, font=f, spacing=3, align="center")
    tw, th = t[2] - t[0], t[3] - t[1]
    d.multiline_text(((bb[0] + bb[2] - tw) / 2 - t[0], (bb[1] + bb[3] - th) / 2 - t[1]),
                     text, font=f, fill=INK, spacing=3, align="center")


def arrow(d, p0, p1, color=(80, 80, 80), width=3, head=11):
    d.line([p0, p1], fill=color, width=width)
    ang = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
    for s in (+1, -1):
        a = ang + s * 0.5
        d.line([p1, (p1[0] - head * math.cos(a), p1[1] - head * math.sin(a))], fill=color, width=width)


def lane(d, y, title, color, items, x0=330, w=196, gap=18, h=88, sz=18):
    d.text((x0, y - 32), title, font=font(21, True), fill=color[1])
    boxes = []
    x = x0
    for t in items:
        b = (x, y, x + w, y + h)
        box(d, b, color, t, sz)
        boxes.append(b)
        x += w + gap
    for i in range(len(boxes) - 1):
        arrow(d, (boxes[i][2], y + h // 2), (boxes[i + 1][0], y + h // 2))
    return boxes


img = Image.new("RGB", (W, H), BG)
d = ImageDraw.Draw(img)

d.text((60, 22), "图 2  系统总体框图（单 FPGA、四通路）", font=font(32, True), fill=INK)

# ---------- 左列：外设 ----------
L_X0, L_W = 60, 210
tf = (L_X0, 150, L_X0 + L_W, 250)
box(d, tf, C_IMG, "TF 卡\nFAT32", 20, True)
sdr = (L_X0, 340, L_X0 + L_W, 470)
box(d, sdr, C_OUT, "板载 SDRAM\n2M×32bit\n四分区帧缓存", 19, True)
tf2 = (L_X0, 560, L_X0 + L_W, 650)
box(d, tf2, C_IMG, "TF 卡\n(FAT32)", 19, True)
key = (L_X0, 760, L_X0 + L_W, 860)
box(d, key, C_CTL, "按键 / 拨码\n4 键 + 4 位", 19, True)

# ---------- 右列：输出 ----------
R_X0 = W - 250
hdmi = (R_X0, 340, R_X0 + 190, 470)
box(d, hdmi, C_OUT, "HDMI 1.4b\nTMDS 4 通道\n640×480@60", 19, True)
seg = (R_X0, 760, R_X0 + 190, 860)
box(d, seg, C_CTL, "数码管 8 位\n图号/音量/状态", 18, True)

# ---------- 四条泳道 ----------
b1 = lane(d, 150, "① 图片通路（sd_card_clk 75MHz）", C_IMG,
          ["SD/SPI 控制器", "FAT32 根目录扫描", "簇链跟随\n(LBA 翻译)", "BMP 解码\n等比缩放"])
b2 = lane(d, 350, "② 显示通路（video_clk 25MHz，逐像素叠加）", C_DIS,
          ["帧读出\n(帧边界切换)", "亮度 / 对比度", "转场\nWIPE / FADE", "2× 商品放大",
           "中文角标\n1bit 掩膜", "OSD / 频谱柱"], w=176)
b3 = lane(d, 560, "③ 音频通路（MCLK 12.288MHz，I2S 64fs）", C_AUD,
          ["PCM 流式播放\nBRAM 缓冲", "音量 / TONE\nQ15 增益", "I2S + ACR\n音画同步",
           "1024 点 DFT\n40 段频谱"], w=196)
b4 = lane(d, 760, "④ 控制通路（50MHz 基准）", C_CTL,
          ["按键消抖\n长短按 / 双击", "菜单控制器\n7 项参数", "翻页 / 切歌\n转场选择",
           "装载状态机\n扫描→装载→常驻"], w=186)

# ---------- 连线（只连相邻块）----------
arrow(d, (tf[2], 200), (b1[0][0], 194))                       # TF -> 图片通路
arrow(d, (b1[-1][0] + 88, b1[-1][3]), (sdr[0] + 105, sdr[1]))  # 解码 -> SDRAM（写）
d.text((b1[-1][0] + 96, b1[-1][3] + 6), "异步 FIFO 写", font=font(15), fill=(90, 90, 90))

arrow(d, (sdr[2], 400), (b2[0][0], 394))                       # SDRAM -> 帧读出（读）
d.text((sdr[2] + 6, 372), "异步 FIFO 读", font=font(15), fill=(90, 90, 90))
arrow(d, (b2[-1][2], 394), (hdmi[0], 394))                     # 显示通路 -> HDMI

arrow(d, (tf2[2], 605), (b3[0][0], 604))                       # TF -> 音频通路
arrow(d, (b3[2][2], 604), (hdmi[0], 440))                      # I2S/ACR -> HDMI（右下进）
arrow(d, (b3[3][0] + 98, b3[3][1]), (b2[5][0] + 88, b2[5][3])) # DFT -> 频谱柱
d.text((b3[3][0] - 6, b3[3][1] - 26), "幅度→柱高", font=font(15), fill=(90, 90, 90))

arrow(d, (key[2], 810), (b4[0][0], 804))                       # 按键 -> 控制通路
arrow(d, (b4[1][0] + 93, b4[1][1]), (b2[5][0] + 20, b2[5][3])) # 菜单控制器 -> OSD
arrow(d, (b4[2][2], 804), (seg[0], 810))                       # 状态 -> 数码管
arrow(d, (b4[2][0] + 93, b4[2][3]), (hdmi[0] + 60, hdmi[3]), color=(120, 120, 120))
d.text((b4[2][0] - 40, 884), "切页信号 → 帧边界提交", font=font(15), fill=(90, 90, 90))

# ---------- 时钟域标注 ----------
clk_y = 930
d.rounded_rectangle((60, clk_y, W - 60, clk_y + 96), radius=12, outline=(180, 180, 180), width=2)
d.text((80, clk_y + 10), "时钟域与跨域处理", font=font(20, True), fill=(60, 60, 60))
d.text((80, clk_y + 42),
       "50MHz 基准 → sys_pll 出 75MHz(SD)、125MHz(SDRAM/HDMI 5×) ；video_pll 出 25MHz(像素)；audio PLL 出 12.288MHz(MCLK)",
       font=font(17), fill=(70, 70, 70))
d.text((80, clk_y + 68),
       "跨域：多 bit 走异步 FIFO（双时钟 BRAM + 格雷码指针）；单 bit 控制两级同步；异步时钟对之间设 set_clock_groups -asynchronous",
       font=font(17), fill=(70, 70, 70))

d.text((60, H - 40), "注：所有切换（翻页、转场、参数变更）均在帧消隐边界生效；显示链路逐像素叠加，无撕裂。",
       font=font(17), fill=(80, 80, 80))

img.save(OUT)
print("已生成:", OUT, img.size)
