# -*- coding: utf-8 -*-
"""重绘 5 张图：学术风（白底、黑细框、直角矩形、无填充、无图内标题、字号大）。
   目标：插入正文 14.4cm 宽后，框内文字 ≥ 9pt。"""
import math
from PIL import Image, ImageDraw, ImageFont

OUT = r"D:\AAA_University\Anlu\Project\doc\报告"
F_B = r"C:\Windows\Fonts\msyhbd.ttc"
F_R = r"C:\Windows\Fonts\msyh.ttc"
INK = (0, 0, 0)
GRAY = (110, 110, 110)


def font(sz, bold=False):
    return ImageFont.truetype(F_B if bold else F_R, sz)


def rect(d, bb, text, sz=30, bold=False, lw=2, fill=None, align_left=False, pad=10):
    d.rectangle(bb, outline=INK, width=lw, fill=fill or (255, 255, 255))
    f = font(sz, bold)
    t = d.multiline_textbbox((0, 0), text, font=f, spacing=6, align="center")
    tw, th = t[2] - t[0], t[3] - t[1]
    if align_left:
        x = bb[0] + pad
    else:
        x = (bb[0] + bb[2] - tw) / 2 - t[0]
    y = (bb[1] + bb[3] - th) / 2 - t[1]
    d.multiline_text((x, y), text, font=f, fill=INK, spacing=6, align="center")


def arrow(d, pts, lw=2, head=12):
    for i in range(len(pts) - 1):
        d.line([pts[i], pts[i + 1]], fill=INK, width=lw)
    p0, p1 = pts[-2], pts[-1]
    ang = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
    for s in (+1, -1):
        a = ang + s * 0.42
        d.line([p1, (p1[0] - head * math.cos(a), p1[1] - head * math.sin(a))], fill=INK, width=lw)


def row(d, items, x0, y, w, h, gap, sz=30, bold=False):
    boxes, x = [], x0
    for t in items:
        b = (x, y, x + w, y + h)
        rect(d, b, t, sz, bold)
        boxes.append(b)
        x += w + gap
    for i in range(len(boxes) - 1):
        arrow(d, [(boxes[i][2], y + h // 2), (boxes[i + 1][0], y + h // 2)])
    return boxes


# ================= 图1 设计流程 =================
W, H = 1320, 560
img = Image.new("RGB", (W, H), (255, 255, 255))
d = ImageDraw.Draw(img)
r1 = row(d, ["需求分析", "方案与模块划分", "RTL 设计", "仿真验证"], 40, 60, 280, 96, 30, 30)
r2 = row(d, ["综合与布局布线", "时序收敛", "上板验证", "固化交付"], 40, 330, 280, 96, 30, 30)
# 行间连接：第1行末 -> 下行首
arrow(d, [(r1[3][0] + 140, r1[3][3]), (r1[3][0] + 140, 240), (40 + 140, 240), (40 + 140, r2[0][1])])
# 回退箭头：仿真 -> RTL
arrow(d, [(r1[3][0] + 140, r1[3][1]), (r1[3][0] + 140, 30), (r1[2][0] + 140, 30), (r1[2][0] + 140, r1[2][1])])
d.text((r1[2][0] + 148, 34), "不通过则回退", font=font(22), fill=GRAY)
img.save(OUT + r"\图1_设计流程图.png")

# ================= 图2 系统总体框图 =================
W, H = 1320, 900
img = Image.new("RGB", (W, H), (255, 255, 255))
d = ImageDraw.Draw(img)
# 左列外设
tf = (30, 90, 220, 170);   rect(d, tf, "TF 卡\n(FAT32)", 26, True)
sdr = (30, 380, 220, 480); rect(d, sdr, "板载 SDRAM\n2M×32bit\n四分区", 24)
kbd = (30, 700, 220, 780); rect(d, kbd, "按键 / 拨码", 26, True)
# 右列输出
hd = (1060, 380, 1290, 480); rect(d, hd, "HDMI 1.4b\n640×480@60", 24)
seg = (1060, 700, 1290, 780); rect(d, seg, "数码管 8 位", 24)

# 四条通路（每条一个整体框，细节见图9）
l1 = row(d, ["SD/SPI\n控制器", "FAT32\n根目录扫描", "BMP 解码\n等比缩放"], 300, 90, 230, 80, 24, 24)
arrow(d, [(tf[2], 130), (l1[0][0], 130)])
arrow(d, [(l1[-1][2], l1[-1][1] + 40), (l1[-1][2] + 20, l1[-1][1] + 40), (l1[-1][2] + 20, 300), (125, 300), (125, sdr[1])])
d.text((l1[-1][2] - 150, 270), "异步 FIFO 写", font=font(20), fill=GRAY)

arrow(d, [(sdr[2], 430), (600, 430)])
b2 = (600, 370, 980, 490)
rect(d, b2, "逐像素叠加\n亮度/对比度 · 转场 · 2× 放大\n中文角标 · OSD · 频谱柱", 22)
arrow(d, [(b2[2], 430), (hd[0], 430)])
d.text((300, 340), "② 显示通路（25MHz 像素时钟）", font=font(22, True), fill=GRAY)

# 音频
l3 = row(d, ["PCM 流式播放\nBRAM 缓冲", "音量 / TONE", "I2S + ACR"], 300, 590, 230, 80, 24, 22)
arrow(d, [(150, 170), (150, 560), (l3[0][0] + 20, 560), (l3[0][0] + 20, l3[0][1])])
arrow(d, [(l3[-1][2], l3[-1][1] + 40), (1030, l3[-1][1] + 40), (1030, hd[1] + 60), (hd[0], hd[1] + 60)])
d.text((300, 540), "③ 音频通路（12.288MHz）", font=font(22, True), fill=GRAY)

# 控制
l4 = ["按键消抖/长短按", "菜单控制器", "翻页 / 切歌"]
boxes4 = l4 and row(d, l4, 300, 700, 230, 80, 24, 24)
arrow(d, [(kbd[2], 740), (boxes4[0][0], 740)])
arrow(d, [(boxes4[2][2], 740), (seg[0], 740)])
d.text((300, 650), "④ 控制通路（50MHz 基准）", font=font(22, True), fill=GRAY)

# 通路编号说明（左侧竖排）
d.text((30, 40), "① 图片通路（75MHz）", font=font(22, True), fill=GRAY)
img.save(OUT + r"\图2_系统总体框图.png")

# ================= 图8 时钟域 =================
W, H = 1320, 660
img = Image.new("RGB", (W, H), (255, 255, 255))
d = ImageDraw.Draw(img)
xtal = (40, 290, 200, 370); rect(d, xtal, "晶振 50MHz", 26, True)
plls = [("sys_pll\n75 / 125MHz", 120), ("video_pll\n25MHz", 300), ("audio_pll\n12.288MHz", 480)]
pl = []
for t, y in plls:
    b = (280, y, 520, y + 80); rect(d, b, t, 24); pl.append(b)
# 总线
arrow(d, [(xtal[2], 330), (240, 330)])
for b in pl:
    arrow(d, [(240, 330), (240, b[1] + 40), (280, b[1] + 40)])
doms = [("控制域 50MHz", 60), ("存储域 75MHz", 150), ("存储域 125MHz", 250),
        ("视频域 25MHz", 360), ("音频域 12.288MHz", 470)]
db = []
for t, y in doms:
    b = (620, y, 950, y + 64); rect(d, b, t, 24); db.append(b)
arrow(d, [(110, xtal[1]), (110, 92), (620, 92)])                    # 晶振 → 控制域
arrow(d, [(520, 160), (620, 182)])                                  # sys → 75
arrow(d, [(520, 160), (570, 160), (570, 282), (620, 282)])          # sys → 125
arrow(d, [(520, 340), (620, 392)])                                  # video → 25
arrow(d, [(520, 520), (620, 502)])                                  # audio → 12.288
# 说明
d.text((620, 570), "多 bit 跨域：异步 FIFO；单 bit：两级同步；异步时钟对设 set_clock_groups -asynchronous",
       font=font(20), fill=GRAY)
img.save(OUT + r"\图8_时钟域.png")

# ================= 图9 叠加管线 =================
W, H = 1320, 300
img = Image.new("RGB", (W, H), (255, 255, 255))
d = ImageDraw.Draw(img)
r = row(d, ["帧读出", "亮度/对比度", "转场\nWIPE/FADE", "2× 放大", "中文角标", "OSD / 频谱", "AXIS 打包"],
        30, 90, 160, 90, 16, 22)
d.text((30, 230), "全部在 25MHz 像素时钟下逐拍完成；翻页与转场在帧消隐边界提交",
       font=font(22), fill=GRAY)
img.save(OUT + r"\图9_叠加管线.png")

# ================= 图10 频谱流程 =================
W, H = 1320, 420
img = Image.new("RGB", (W, H), (255, 255, 255))
d = ImageDraw.Draw(img)
r = row(d, ["增益后 PCM", "取 1024 点", "Q15 定点 DFT", "|I|+|Q|", "对数分 40 段"], 30, 60, 230, 90, 20, 24)
r2 = row(d, ["平滑 + 峰值保持", "渲染最底行 40 段"], 30, 220, 330, 90, 30, 24)
arrow(d, [(r[-1][0] + 115, r[-1][3]), (r[-1][0] + 115, 170), (r2[0][0] + 165, 170), (r2[0][0] + 165, r2[0][1])])
d.text((30, 350), "每 42 帧刷新；无 AGC，固定参考映射；柱高与音量整体联动",
       font=font(22), fill=GRAY)
img.save(OUT + r"\图10_频谱流程.png")

print("已重绘 5 张图（学术风）")
