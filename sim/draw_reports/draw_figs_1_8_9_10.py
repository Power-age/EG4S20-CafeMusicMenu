# -*- coding: utf-8 -*-
"""绘制图1（设计流程）、图8（时钟域）、图9（叠加管线）、图10（频谱流程）。
风格与图2保持一致：白底、圆角卡片、灰细边框、深灰文字。"""
import math
from PIL import Image, ImageDraw, ImageFont

OUT_DIR = r"D:\AAA_University\Anlu\Project\doc\报告"
F_B = r"C:\Windows\Fonts\msyhbd.ttc"
F_R = r"C:\Windows\Fonts\msyh.ttc"
INK = (30, 30, 30)
GREY = (90, 90, 90)


def font(sz, bold=False):
    return ImageFont.truetype(F_B if bold else F_R, sz)


def box(d, bb, text, fill, edge, sz=19, bold=False, r=10):
    d.rounded_rectangle(bb, radius=r, fill=fill, outline=edge, width=2)
    f = font(sz, bold)
    t = d.multiline_textbbox((0, 0), text, font=f, spacing=3, align="center")
    tw, th = t[2] - t[0], t[3] - t[1]
    d.multiline_text(((bb[0] + bb[2] - tw) / 2 - t[0], (bb[1] + bb[3] - th) / 2 - t[1]),
                     text, font=f, fill=INK, spacing=3, align="center")


def poly_arrow(d, pts, color=GREY, width=3, head=11):
    for i in range(len(pts) - 1):
        d.line([pts[i], pts[i + 1]], fill=color, width=width)
    p0, p1 = pts[-2], pts[-1]
    ang = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
    for s in (+1, -1):
        a = ang + s * 0.5
        d.line([p1, (p1[0] - head * math.cos(a), p1[1] - head * math.sin(a))], fill=color, width=width)


def chain(img_dir, W, H, title, items, fill, edge, y=250, box_w=200, box_h=96, gap=44, sz=19, two_rows=False):
    img = Image.new("RGB", (W, H), (255, 255, 255))
    d = ImageDraw.Draw(img)
    d.text((MAX, 26), title, font=font(30, True), fill=INK)
    boxes, x = [], 60
    per_row = len(items) if not two_rows else (len(items) + 1) // 2
    for i, t in enumerate(items):
        if two_rows and i == per_row:
            x = 60
        yy = y if (not two_rows or i < per_row) else y + box_h + 110
        b = (x, yy, x + box_w, yy + box_h)
        box(d, b, t, fill, edge, sz)
        boxes.append(b)
        x += box_w + gap
    for i in range(len(boxes) - 1):
        if two_rows and i == per_row - 1:
            continue
        poly_arrow(d, [(boxes[i][2], boxes[i][1] + box_h // 2), (boxes[i + 1][0], boxes[i + 1][1] + box_h // 2)])
    if two_rows:
        # 第一行末尾折到第二行开头
        a = boxes[per_row - 1]
        b = boxes[per_row]
        poly_arrow(d, [(a[0] + box_w // 2, a[3]), (a[0] + box_w // 2, (a[3] + b[1]) // 2),
                       (b[0] + box_w // 2, (a[3] + b[1]) // 2), (b[0] + box_w // 2, b[1])])
    return img, d, boxes


MAX = 60

# ---------------- 图1 设计流程 ----------------
W, H = 1600, 520
img = Image.new("RGB", (W, H), (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((60, 26), "图 1  作品设计流程", font=font(30, True), fill=INK)
steps = ["需求分析\n（赛题 + 用户）", "方案与\n模块划分", "RTL 设计\n（Verilog）", "仿真验证\n（画帧/黄金值）",
         "综合与\n布局布线", "时序收敛\n（建立+保持）", "上板验证\n（逐项功能）", "固化与\n交付"]
bw, bh, gap, y = 172, 96, 26, 150
boxes, x = [], 60
for s in steps:
    b = (x, y, x + bw, y + bh)
    box(d, b, s, (232, 240, 254), (66, 110, 180), 17)
    boxes.append(b)
    x += bw + gap
for i in range(len(boxes) - 1):
    poly_arrow(d, [(boxes[i][2], y + bh // 2), (boxes[i + 1][0], y + bh // 2)])
# 回退箭头
poly_arrow(d, [(boxes[3][0] + bw // 2, boxes[3][3]), (boxes[3][0] + bw // 2, 300),
               (boxes[2][0] + bw // 2, 300), (boxes[2][0] + bw // 2, boxes[2][3])], color=(200, 80, 80))
d.text((boxes[2][0] + 6, 308), "不通过则回退修改", font=font(16), fill=(200, 80, 80))
d.text((60, 400), "原则：小步推进、每项功能独立构建并保留可回退稳定点；构建脚本设门禁——"
                  "建立与保持时间不全部达标，不更新交付件。", font=font(18), fill=(70, 70, 70))
img.save(OUT_DIR + r"\图1_设计流程图.png")

# ---------------- 图8 时钟域 ----------------
W, H = 1680, 800
img = Image.new("RGB", (W, H), (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((60, 26), "图 8  时钟域划分与跨时钟域处理", font=font(30, True), fill=INK)

# 左：晶振
xtal = (60, 330, 250, 420)
box(d, xtal, "板载晶振\n50MHz", (236, 236, 236), (110, 110, 110), 19, True)

# 中：三个 PLL
plls = [("sys_pll", "75MHz / 125MHz", (226, 238, 255), (52, 101, 164), 150),
        ("video_pll", "25MHz（像素）", (228, 245, 232), (46, 125, 79), 330),
        ("audio_pll", "12.288MHz（MCLK）", (255, 241, 224), (186, 106, 24), 510)]
pll_boxes = {}
for name, desc, fill, edge, y in plls:
    b = (330, y, 330 + 400, y + 76)
    box(d, b, "%s：%s" % (name, desc), fill, edge, 18)
    pll_boxes[name] = b

# 右侧：五个时钟域
doms = [("控制域 50MHz\n按键/菜单/数码管/状态机", (242, 234, 252), (106, 70, 160), 60),
        ("存储域 75MHz\nSD 卡读写 / FAT32 / BMP", (226, 238, 255), (52, 101, 164), 160),
        ("存储域 125MHz\nSDRAM 读写 / HDMI 5×", (226, 238, 255), (52, 101, 164), 260),
        ("视频域 25MHz\n叠加 / OSD / AXIS", (228, 245, 232), (46, 125, 79), 360),
        ("音频域 12.288MHz\nPCM 播放 / DFT", (255, 241, 224), (186, 106, 24), 460)]
dom_boxes = {}
for name, fill, edge, y in doms:
    b = (830, y, 830 + 420, y + 76)
    box(d, b, name, fill, edge, 17)
    dom_boxes[name.split(" ")[0]] = b

# 总线：晶振 → 三 PLL
bus_x = 292
poly_arrow(d, [(xtal[2], 375), (bus_x, 375)])
for name, desc, fill, edge, y in plls:
    poly_arrow(d, [(bus_x, 375), (bus_x, y + 38), (330, y + 38)])
# 晶振 → 控制域（直上）
poly_arrow(d, [(210, xtal[1]), (210, 98), (830, 98)])
# PLL → 域
poly_arrow(d, [(330 + 400, 150 + 38), (830, 160 + 38)])   # sys → 75MHz
poly_arrow(d, [(330 + 400, 150 + 38), (700, 150 + 38), (700, 260 + 38), (830, 260 + 38)])  # sys → 125MHz
poly_arrow(d, [(330 + 400, 330 + 38), (830, 360 + 38)])   # video → 25MHz
poly_arrow(d, [(330 + 400, 510 + 38), (830, 460 + 38)])   # audio → 12.288MHz

# CDC 说明
cdc_y = 620
d.rounded_rectangle((60, cdc_y, W - 60, cdc_y + 130), radius=12, outline=(180, 180, 180), width=2)
d.text((82, cdc_y + 10), "跨时钟域处理", font=font(20, True), fill=(60, 60, 60))
d.text((82, cdc_y + 44), "多 bit 数据：异步 FIFO（双时钟 BRAM + 格雷码指针）——SD→SDRAM、SDRAM→视频、PCM→音频、视频→HDMI 串行", font=font(17), fill=(70, 70, 70))
d.text((82, cdc_y + 72), "单 bit 控制：两级寄存器同步（按键、切页请求、参数更新等）", font=font(17), fill=(70, 70, 70))
d.text((82, cdc_y + 100), "约束：异步时钟对之间设 set_clock_groups -asynchronous；九个时钟域建立与保持时间均 0 违例", font=font(17), fill=(70, 70, 70))
img.save(OUT_DIR + r"\图8_时钟域.png")
# ---------------- 图9 叠加管线 ----------------
W, H = 1600, 470
img = Image.new("RGB", (W, H), (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((60, 26), "图 9  逐像素显示叠加管线（25MHz 像素时钟）", font=font(30, True), fill=INK)
stages = ["帧读出\n（帧缓存）", "亮度", "对比度", "转场\nWIPE/FADE", "2× 商品放大",
          "中文角标\n1bit 掩膜", "OSD\n面板/倒计时", "40 段频谱", "AXIS\n打包"]
bw, bh, gap, y = 150, 92, 22, 130
boxes, x = [], 60
for s in stages:
    b = (x, y, x + bw, y + bh)
    box(d, b, s, (228, 245, 232), (46, 125, 79), 16)
    boxes.append(b)
    x += bw + gap
for i in range(len(boxes) - 1):
    poly_arrow(d, [(boxes[i][2], y + bh // 2), (boxes[i + 1][0], y + bh // 2)])
d.rounded_rectangle((60, 280, W - 60, 380), radius=12, outline=(180, 180, 180), width=2)
d.text((82, 292), "关键约定", font=font(20, True), fill=(60, 60, 60))
d.text((82, 326), "① 全部叠加在像素级逐拍完成，像素时钟 25MHz；② 翻页/转场/参数变更在帧消隐边界提交，画面无撕裂；"
                  "③ 角标与频谱叠加在 AXIS 打包之前。", font=font(17), fill=(70, 70, 70))
img.save(OUT_DIR + r"\图9_叠加管线.png")

# ---------------- 图10 频谱流程 ----------------
W, H = 1600, 560
img = Image.new("RGB", (W, H), (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((60, 26), "图 10  音频频谱可视化处理流程", font=font(30, True), fill=INK)
st = ["增益后 PCM\n48kHz", "分块取 1024 点\n（加窗）", "Q15 定点 DFT\n正余弦表",
      "幅度 |I|+|Q|\n（L1 范数）", "对数分 40 段\n（映射为柱高）", "平滑 + 峰值保持\n（跨频 3 点 / 帧间低通）",
      "渲染到最底行\n40 段柱形"]
bw, bh, gap, y = 190, 96, 26, 130
boxes, x = [], 60
for s in st:
    b = (x, y, x + bw, y + bh)
    box(d, b, s, (255, 241, 224), (186, 106, 24), 16)
    boxes.append(b)
    x += bw + gap
for i in range(len(boxes) - 1):
    poly_arrow(d, [(boxes[i][2], y + bh // 2), (boxes[i + 1][0], y + bh // 2)])
d.rounded_rectangle((60, 300, W - 60, 470), radius=12, outline=(180, 180, 180), width=2)
d.text((82, 314), "实现要点", font=font(20, True), fill=(60, 60, 60))
for i, t in enumerate([
        "① 每 42 帧刷新一次，避免柱形抖动；无 AGC，采用固定参考映射，音量变化时柱高整体跟随；",
        "② TONE 测试音频率取 k×46.875Hz，恰好落在 DFT 频点上，可直接验证频谱通路；",
        "③ 柱形渲染在画面最底行（y=479），高 63px，不遮挡上方图文。"]):
    d.text((82, 350 + i * 30), t, font=font(17), fill=(70, 70, 70))
img.save(OUT_DIR + r"\图10_频谱流程.png")

print("已生成：图1 / 图8 / 图9 / 图10")
