# -*- coding: utf-8 -*-
"""最终版 5 张图：黑白学术风、双列走廊布局、画布缩小以放大字号。
   画布宽 1100~1200px，插入正文 14.4cm 后框内文字约 8.5~10pt。"""
import math
from PIL import Image, ImageDraw, ImageFont

OUT = r"D:\AAA_University\Anlu\Project\doc\报告"
F_B = r"C:\Windows\Fonts\msyhbd.ttc"
F_R = r"C:\Windows\Fonts\msyh.ttc"
INK = (0, 0, 0)
GRAY = (100, 100, 100)


def font(sz, bold=False):
    return ImageFont.truetype(F_B if bold else F_R, sz)


def rect(d, bb, text, sz=26, bold=False, lw=2):
    d.rectangle(bb, outline=INK, width=lw, fill=(255, 255, 255))
    f = font(sz, bold)
    t = d.multiline_textbbox((0, 0), text, font=f, spacing=5, align="center")
    tw, th = t[2] - t[0], t[3] - t[1]
    d.multiline_text(((bb[0] + bb[2] - tw) / 2 - t[0], (bb[1] + bb[3] - th) / 2 - t[1]),
                     text, font=f, fill=INK, spacing=5, align="center")


def arrow(d, pts, lw=2, head=11):
    for i in range(len(pts) - 1):
        d.line([pts[i], pts[i + 1]], fill=INK, width=lw)
    p0, p1 = pts[-2], pts[-1]
    ang = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
    for s in (+1, -1):
        a = ang + s * 0.42
        d.line([p1, (p1[0] - head * math.cos(a), p1[1] - head * math.sin(a))], fill=INK, width=lw)


def note(d, x, y, t, sz=20):
    d.text((x, y), t, font=font(sz), fill=GRAY)


# ==================== 图1 设计流程 ====================
W, H = 1150, 500
img = Image.new("RGB", (W, H), (255, 255, 255))
d = ImageDraw.Draw(img)
r1 = ["需求分析", "方案与\n模块划分", "RTL 设计", "仿真验证"]
r2 = ["综合与\n布局布线", "时序收敛", "上板验证", "固化交付"]
bw, bh, gap = 240, 86, 33
b1, x = [], 40
for t in r1:
    b = (x, 78, x + bw, 78 + bh); rect(d, b, t, 27); b1.append(b); x += bw + gap
b2, x = [], 40
for t in r2:
    b = (x, 320, x + bw, 320 + bh); rect(d, b, t, 27); b2.append(b); x += bw + gap
for i in range(3):
    arrow(d, [(b1[i][2], 78 + bh // 2), (b1[i + 1][0], 78 + bh // 2)])
    arrow(d, [(b2[i][2], 320 + bh // 2), (b2[i + 1][0], 320 + bh // 2)])
arrow(d, [(b1[3][0] + bw // 2, b1[3][3]), (b1[3][0] + bw // 2, 235), (b2[0][0] + bw // 2, 235), (b2[0][0] + bw // 2, b2[0][1])])
arrow(d, [(b1[3][0] + bw // 2, b1[3][1]), (b1[3][0] + bw // 2, 44), (b1[2][0] + bw // 2, 44), (b1[2][0] + bw // 2, b1[2][1])])
note(d, b1[2][0] + bw // 2 + 12, 18, "不通过则回退")
note(d, 40, 430, "小步推进：每项功能独立构建并保留可回退稳定点；时序未全部达标不更新交付件", 21)
img.save(OUT + r"\图1_设计流程图.png")

# ==================== 图2 系统总体框图 ====================
W, H = 1120, 700
img = Image.new("RGB", (W, H), (255, 255, 255))
d = ImageDraw.Draw(img)
LC0, LC1 = 50, 420
RC0, RC1 = 640, 1070
BH = 76
def blk(x0, x1, y, text, sz=23, bold=False):
    b = (x0, y, x1, y + BH); rect(d, b, text, sz, bold); return b

# 左列：数据通路（自上而下）
L1 = blk(LC0, LC1, 40,  "TF 卡（FAT32）", 24, True)
L2 = blk(LC0, LC1, 160, "图片读取与解码\nSD/SPI · FAT32 · 簇链 · BMP 解码")
L3 = blk(LC0, LC1, 280, "板载 SDRAM\n四分区帧缓存")
L4 = (LC0, 400, LC1, 512)
rect(d, L4, "逐像素叠加\n亮度 / 对比度 · 转场 · 2× 放大\n中文角标 · OSD · 频谱", 21)
L5 = blk(LC0, LC1, 560, "HDMI 1.4b 发送\n640×480@60 + 音频包", 22)
for a, b in [(L1, L2), (L2, L3), (L3, L4), (L4, L5)]:
    arrow(d, [((a[0] + a[2]) // 2, a[3]), ((b[0] + b[2]) // 2, b[1])])

# 右列：控制与音频（自下而下，间距 110）
R1 = blk(RC0, RC1, 40,  "按键 / 拨码", 24, True)
R2 = blk(RC0, RC1, 160, "消抖与菜单控制\n长短按 · 7 项参数")
R3 = blk(RC0, RC1, 280, "TF 卡（音频）", 23)
R4 = blk(RC0, RC1, 400, "PCM 流式播放 · 音量 / TONE", 22)
R5 = blk(RC0, RC1, 520, "I2S + ACR 组帧\n1024 点 DFT · 40 段频谱", 22)
for a, b in [(R1, R2), (R2, R3), (R3, R4), (R4, R5)]:
    arrow(d, [((a[0] + a[2]) // 2, a[3]), ((b[0] + b[2]) // 2, b[1])])

# 跨列连线：全部走 420~640 的空白走廊
arrow(d, [(RC0, 198), (600, 198), (600, 450), (LC1, 450)])      # 切页/参数 → 叠加
note(d, 448, 168, "切页 / 参数")
arrow(d, [(RC0, 545), (560, 545), (560, 484), (LC1, 484)])      # 频谱 → 叠加
note(d, 470, 506, "频谱")
arrow(d, [(RC0, 592), (LC1, 592)])                              # 音频 → HDMI
note(d, 470, 598, "音频")
note(d, 50, 650, "注：跨时钟域数据经异步 FIFO；单 bit 控制两级同步；所有切换在帧消隐边界生效。", 20)
img.save(OUT + r"\图2_系统总体框图.png")
# ==================== 图8 时钟域（一对一直线） ====================
W, H = 1120, 560
img = Image.new("RGB", (W, H), (255, 255, 255))
d = ImageDraw.Draw(img)

xtal = (40, 375, 200, 455)
rect(d, xtal, "晶振 50MHz", 24, True)

# 三个 PLL：sys 拉高，覆盖 75/125 两个输出高度
sys  = (270, 90, 500, 240)
vid  = (270, 280, 500, 350)
aud  = (270, 420, 500, 490)
rect(d, sys, "sys_pll\n75 / 125MHz", 23)
rect(d, vid, "video_pll\n25MHz", 23)
rect(d, aud, "audio_pll\n12.288MHz", 23)

# 五个时钟域，与 PLL 输出严格同高
d_ctrl = (640, 30, 1020, 88)
d_75   = (640, 96, 1020, 154)
d_125  = (640, 176, 1020, 234)
d_vid  = (640, 286, 1020, 344)
d_aud  = (640, 426, 1020, 484)
for b, tx in [(d_ctrl, "控制域 50MHz"), (d_75, "存储域 75MHz"), (d_125, "存储域 125MHz"),
              (d_vid, "视频域 25MHz"), (d_aud, "音频域 12.288MHz")]:
    rect(d, b, tx, 23)

# 晶振 -> 三条支路（竖直总线 x=235）
arrow(d, [(xtal[2], 415), (235, 415)])
arrow(d, [(235, 415), (235, 165), (270, 165)])   # -> sys_pll
arrow(d, [(235, 415), (235, 315), (270, 315)])   # -> video_pll
arrow(d, [(235, 415), (235, 455), (270, 455)])   # -> audio_pll

# 晶振 -> 控制域（走左侧上方）
arrow(d, [(120, 375), (120, 59), (640, 59)])

# PLL -> 时钟域：全部为水平直线
arrow(d, [(500, 125), (640, 125)])   # sys 75MHz
arrow(d, [(500, 205), (640, 205)])   # sys 125MHz
arrow(d, [(500, 315), (640, 315)])   # video 25MHz
arrow(d, [(500, 455), (640, 455)])   # audio 12.288MHz

note(d, 40, 520, "多 bit 跨域走异步 FIFO，单 bit 两级同步；异步时钟对设 set_clock_groups", 21)
img.save(OUT + r"\图8_时钟域.png")
# ==================== 图9 叠加管线（两行） ====================
W, H = 1150, 420
img = Image.new("RGB", (W, H), (255, 255, 255))
d = ImageDraw.Draw(img)
bw, bh, gap = 240, 86, 33
row1 = ["帧读出", "亮度 / 对比度", "转场 WIPE/FADE", "2× 商品放大"]
row2 = ["中文角标（掩膜）", "OSD / 频谱柱", "AXIS 打包"]
b1, x = [], 40
for tx in row1:
    b = (x, 50, x + bw, 50 + bh); rect(d, b, tx, 24); b1.append(b); x += bw + gap
b2, x = [], 40
for tx in row2:
    b = (x, 270, x + bw, 270 + bh); rect(d, b, tx, 24); b2.append(b); x += bw + gap
for i in range(3):
    arrow(d, [(b1[i][2], 50 + bh // 2), (b1[i + 1][0], 50 + bh // 2)])
for i in range(2):
    arrow(d, [(b2[i][2], 270 + bh // 2), (b2[i + 1][0], 270 + bh // 2)])
arrow(d, [(b1[3][0] + bw // 2, b1[3][3]), (b1[3][0] + bw // 2, 200), (b2[0][0] + bw // 2, 200), (b2[0][0] + bw // 2, b2[0][1])])
note(d, 40, 370, "全部在 25MHz 像素时钟下逐拍完成；翻页与转场在帧消隐边界提交", 21)
img.save(OUT + r"\图9_叠加管线.png")
# ==================== 图10 频谱流程 ====================
W, H = 1180, 330
img = Image.new("RGB", (W, H), (255, 255, 255))
d = ImageDraw.Draw(img)
items = ["增益后 PCM", "取 1024 点", "Q15 定点 DFT", "|I| + |Q|", "对数分 40 段"]
bw, gap, x = 206, 22, 30
bs = []
for t in items:
    b = (x, 50, x + bw, 132); rect(d, b, t, 23); bs.append(b); x += bw + gap
for i in range(len(bs) - 1):
    arrow(d, [(bs[i][2], 91), (bs[i + 1][0], 91)])
b6 = (30, 210, 330, 292); rect(d, b6, "平滑 + 峰值保持", 23)
b7 = (360, 210, 660, 292); rect(d, b7, "渲染最底行 40 段", 23)
arrow(d, [(bs[2][0] + 103, bs[2][3]), (bs[2][0] + 103, 170), (b6[0] + 150, 170), (b6[0] + 150, b6[1])])
arrow(d, [(b6[2], 251), (b7[0], 251)])
note(d, 700, 240, "每 42 帧刷新；固定参考映射", 21)
img.save(OUT + r"\图10_频谱流程.png")

print("5 张图已重绘（黑白、双列走廊、画布 1120~1180）")
