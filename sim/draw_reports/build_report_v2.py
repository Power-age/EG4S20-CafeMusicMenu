# -*- coding: utf-8 -*-
"""
以官方模板为基底生成技术报告：
  - 保留模板的段落样式（Heading 2 / Normal 14pt 加粗 / List Paragraph 自动编号）
  - 正文用模板的 12pt 宋体（小四）
  - 图片、表格插入到模板对应位置
  - 实物照片位置保留红色占位符
"""
import io, os, re
import docx
from docx.shared import Pt, Cm, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn
from copy import deepcopy

TPL = r"D:\AAA_University\Anlu\官方文件\材料上交\报告\技术报告模板.docx"
OUT_DIR = r"D:\AAA_University\Anlu\Project\doc\报告"
OUT = os.path.join(OUT_DIR, "技术报告_木与豆咖啡.docx")
FIG = os.path.join(OUT_DIR, "图%s_%s.png")

doc = docx.Document(TPL)
paras = list(doc.paragraphs)          # 快照（后续会插入新段落）
TPL_IDS = set(id(p._p) for p in paras)   # 模板原有段落，后处理时不动

# 找格式捐赠者
def find(prefix):
    for p in paras:
        if p.text.strip().startswith(prefix):
            return p
    return None

body_donor = find("800字内")            # List Paragraph，无编号，12pt
if body_donor is None:
    raise SystemExit("找不到正文样式捐赠段")

def add_after(anchor_p, text, indent=True, bold=False, size=None, align=None, color=None):
    """在 anchor_p 之后插入一段，复制正文样式。"""
    np = deepcopy(body_donor._p)
    anchor_p._p.addnext(np)
    from docx.text.paragraph import Paragraph
    para = Paragraph(np, anchor_p._parent)
    # 清空多余 run，仅留第一个
    for r in para.runs[1:]:
        r._element.getparent().remove(r._element)
    if not para.runs:
        para.add_run("")
    run = para.runs[0]
    run.text = text
    # 字体：模板已是 12pt 宋体/Times New Roman
    if size:
        run.font.size = Pt(size)
    if bold:
        run.font.bold = True
    if color:
        run.font.color.rgb = color
    pf = para.paragraph_format
    pf.first_line_indent = Pt(24) if indent else Pt(0)
    pf.space_before = Pt(2)
    pf.space_after = Pt(2)
    pf.line_spacing = 1.5
    if align is not None:
        para.alignment = align
    return para

def add_pic_after(anchor_p, path, width_cm, caption):
    if not os.path.exists(path):
        para = add_after(anchor_p, "【缺图：%s】" % os.path.basename(path), indent=False,
                         bold=True, color=RGBColor(0xC0, 0, 0), align=WD_ALIGN_PARAGRAPH.CENTER)
        return para
    np = deepcopy(body_donor._p)
    anchor_p._p.addnext(np)
    from docx.text.paragraph import Paragraph
    para = Paragraph(np, anchor_p._parent)
    for r in para.runs[1:]:
        r._element.getparent().remove(r._element)
    run = para.runs[0] if para.runs else para.add_run("")
    run.text = ""
    para.alignment = WD_ALIGN_PARAGRAPH.CENTER
    para.paragraph_format.first_line_indent = Pt(0)
    para.add_run().add_picture(path, width=Cm(width_cm))
    # 图注
    cap = add_after(para, caption, indent=False, size=10.5, align=WD_ALIGN_PARAGRAPH.CENTER)
    return cap

def add_placeholder(anchor_p, text):
    return add_after(anchor_p, text, indent=False, bold=True,
                     color=RGBColor(0xC0, 0, 0), align=WD_ALIGN_PARAGRAPH.CENTER)

def add_table_after(anchor_p, title, rows):
    cap = add_after(anchor_p, title, indent=False, size=10.5, bold=True, align=WD_ALIGN_PARAGRAPH.CENTER)
    cap.paragraph_format.keep_with_next = True      # 题注与表同页
    t = doc.add_table(rows=len(rows), cols=len(rows[0]))
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    # 模板没有 Table Grid 样式，手工加单线边框
    from docx.oxml import OxmlElement
    tblPr = t._tbl.tblPr
    borders = OxmlElement('w:tblBorders')
    for edge in ('top', 'left', 'bottom', 'right', 'insideH', 'insideV'):
        el = OxmlElement('w:' + edge)
        el.set(qn('w:val'), 'single'); el.set(qn('w:sz'), '4')
        el.set(qn('w:space'), '0'); el.set(qn('w:color'), '000000')
        borders.append(el)
    tblPr.append(borders)
    for i, row in enumerate(rows):
        for j, cell in enumerate(row):
            c = t.cell(i, j)
            c.text = ""
            pr = c.paragraphs[0]
            pr.alignment = WD_ALIGN_PARAGRAPH.CENTER
            rr = pr.add_run(cell)
            rr.font.size = Pt(9)
            rr.font.name = "宋体"
            rr._element.rPr.rFonts.set(qn("w:eastAsia"), "宋体")
            rr.font.bold = (i == 0)
    # 表头跨页重复 + 单行不跨页
    from docx.oxml import OxmlElement as _OE
    for i, row in enumerate(t.rows):
        trPr = row._tr.get_or_add_trPr()
        cant = _OE('w:cantSplit')
        trPr.append(cant)
        if i == 0:
            th = _OE('w:tblHeader')
            trPr.append(th)
    cap._p.addnext(t._tbl)
    # 返回表格之后的一个空段落，便于继续往后插内容
    np = deepcopy(body_donor._p)
    t._tbl.addnext(np)
    from docx.text.paragraph import Paragraph
    p_after = Paragraph(np, cap._parent)
    for r in p_after.runs[1:]:
        r._element.getparent().remove(r._element)
    if p_after.runs:
        p_after.runs[0].text = ""
    return p_after

# ================== 填充内容 ==================
def para_by(prefix):
    for p in paras:
        if p.text.strip().startswith(prefix):
            return p
    return None

# 0. 作品名称
title_p = para_by("作品名称")
if title_p is not None and title_p.runs:
    title_p.runs[0].text = "木与豆咖啡 · 店内音乐电子菜单"
    for r in title_p.runs[1:]:
        r._element.getparent().remove(r._element)

sub_p = para_by("（不要出现任何涉及学校名称")
if sub_p is not None and sub_p.runs:
    sub_p.runs[0].text = "——基于安路 EG4S20 的单 FPGA 店内音乐电子菜单"
    sub_p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    for r in sub_p.runs[1:]:
        r._element.getparent().remove(r._element)

# 1. 摘要
abstract = [
 "本作品是一台置于咖啡店柜台的电子菜单板，面向数字广告牌与商业展陈终端场景，是 2026 全国大学生嵌入式芯片与系统设计竞赛 FPGA 创新设计赛道（安路赛道）选题一的完整实现。"
 "整机只有一颗安路 EG4S20 FPGA，无处理器、无操作系统：从 TF 卡读取、图像缩放、图层叠加到 HDMI 输出全部由硬件逻辑完成，上电即自动轮播四页商品海报并播放背景音乐，底部频谱随音乐起伏。",
 "上电后 FPGA 扫描 FAT32 格式 TF 卡，将四张不同分辨率的商品海报（1280×960、1280×960、1280×720、400×400）解码后按比例适配到 640×480 输出，"
 "居中并自动补黑边，常驻板载 2M×32bit SDRAM 的四个分区；翻页只改分区号，在帧消隐边界切换，零加载、无撕裂。48kHz 音乐以裸 PCM 流式读出，经 HDMI 与画面同步播放；"
 "曲目切换、快进快退、音量、亮度、对比度均可用板载按键与拨码完成，并在 OSD 上回显。",
 "在满足赛题基础要求之外，作品实现了中文叠加、转场、局部放大、实时参数调节与音频可视化五项扩展：商品名与卖点以 1bit 掩膜由 FPGA 逐像素叠加，"
 "左上角中文角标随翻页滑入并在设置面板打开时依然显示；支持揭幕与黑场两种转场；支持 2 倍双线性局部放大且放大窗口按页对准商品；"
 "对 PCM 实时做 1024 点定点 DFT，按对数分为 40 段频谱贴底部渲染。",
 "最终版本资源占用为 slices 87.74%、BRAM9K 15/64、DSP 11/29；布局布线后九个时钟域建立与保持时间全部无违例（显示主通路建立裕量 +11.73ns）。"
 "比特流已固化至 QSPI Flash，断电重启后自动运行、无需 PC，换卡即换菜单。",
]
anchor = para_by("800字内")
for i, t in enumerate(abstract):
    anchor = add_after(anchor, t)

# 2. 功能与特性
feat = [
 "（1）多分辨率自适应播放：识别 FAT32 根目录 PIC1~PIC4.BMP，四页分辨率不同（1280×960、1280×960、1280×720、400×400），按比例适配 640×480 并自动补黑边，手动翻页或自动轮播；",
 "（2）背景音乐：48kHz 裸 PCM 经 HDMI 与画面同步播放，支持 16 档音量、曲目切换与 ±10 秒快进快退；",
 "（3）中文叠加：左上角中文角标（每页不同文案）与商品卖点以 1bit 掩膜由 FPGA 叠加，翻页时滑入，设置面板打开时仍正常显示；",
 "（4）转场与放大：揭幕、黑场两种转场；2 倍双线性放大，放大窗口按页对准商品，封面不放大；",
 "（5）实时调节与可视化：亮度、对比度、音量实时可调并在 OSD 回显；40 段频谱贴屏幕最底行随音乐起伏；",
 "（6）可靠性：四分区常驻、切图零加载；比特流固化 Flash，上电自启、长期无人值守运行。",
]
anchor = para_by("400字内（可加重要图）")
for t in feat:
    anchor = add_after(anchor, t)

# 3. 应用领域
app = [
 "作品定位为门店菜单板、数字广告牌与商业展陈终端，典型场景是咖啡店、烘焙店、甜品店的柜台：设备上电即播，无需电脑、手机或联网；"
 "店员换菜单只需换 TF 卡内容，无需专业维护；四页图文循环展示，背景音乐与频谱营造氛围，亮度、对比度、音量可在现场即时调整。",
 "其平台化硬件底座可推广到更多场景：餐厅与奶茶店的点餐价格屏、门店与展台广告欢迎屏、酒店楼宇信息发布屏、教室与会议室展示终端。"
 "图片（FAT32→BMP→帧缓存→HDMI）、音频（PCM→DFT→HDMI）、交互（按键/拨码/OSD）三条通路相互独立，可分别复用为电子相册、音频可视化装置与信息发布终端。",
]
anchor = para_by("400字内（可加重要图）")
# 第二个"400字内"才是应用领域
cands = [p for p in paras if p.text.strip().startswith("400字内（可加重要图）")]
if len(cands) >= 2:
    anchor = cands[1]
for t in app:
    anchor = add_after(anchor, t)

# 4. 主要技术特点
tech = [
 "（1）纯硬件、无操作系统：全部功能由 FPGA 逻辑实现，无外部 CPU 与软件，状态确定、上电即播；",
 "（2）四分区常驻零加载：四张图上电后常驻 SDRAM 四个分区，翻页只改分区号，在帧消隐边界原子生效，无加载等待、无撕裂；",
 "（3）真实 DFT 频谱：对增益后 PCM 实时做 1024 点 Q15 定点 DFT、对数分 40 段，配合跨频平滑、峰值保持与固定参考映射，柱形稳定不抖；",
 "（4）位图掩膜叠加：4 页中文角标掩膜合成 4096×32bit 只读 ROM 固化进 BRAM，文字与底图分层、逐像素叠加，随翻页滑入；",
 "（5）多分辨率自适应：按页读取各图原始宽高，等比缩放并计算居中偏移，四页分辨率不同也能满幅显示且不拉伸；",
 "（6）规范多时钟域：50/75/125/25/12.288MHz 多域之间，多 bit 数据走异步 FIFO、单 bit 控制两级同步，"
 "SDC 约束完整，最终九个时钟域建立与保持时间零违例。",
]
anchor = para_by("400字内；")
if anchor is None:
    anchor = [p for p in paras if p.text.strip().startswith("400字内")][2]
for t in tech:
    anchor = add_after(anchor, t)

# 5. 主要性能指标
anchor = para_by("200字内（建议用表格）")
anchor = add_after(anchor, "主要性能指标见表 1，资源与时序数据取自最终固化版本的安路 TD（Tang Dynasty 5.6.2）综合与布局布线报告。")
add_table_after(anchor, "表1  主要性能指标", [
    ("项目", "指标 / 说明"),
    ("显示 / 刷新率", "640×480@60Hz（VIC=1），像素时钟 25MHz"),
    ("视频接口", "HDMI 1.4b，TMDS 3 数据 + 1 时钟，10bit 串行"),
    ("音频", "48kHz、16bit 单声道，HDMI 音频包，ACR 同步（N=6144）"),
    ("菜单页面", "4 页：1280×960、1280×960、1280×720、400×400（方图），自动补黑边"),
    ("帧缓存", "板载 SDRAM 2M×32bit（8MB），四分区常驻"),
    ("中文角标", "1bit 掩膜 ROM 4096×32bit，26px 高，翻页滑入"),
    ("音频频谱", "1024 点 DFT，40 段对数分箱，贴最底行渲染"),
    ("资源占用", "slices 87.74%，BRAM9K 15/64，DSP 11/29"),
    ("时序", "九个时钟域 setup/hold 全部 0 违例"),
    ("启动方式", "QSPI Flash 固化，上电自启，无需 PC"),
])

# 6. 主要创新点
inn = [
 "（1）实时 DFT 音频可视化：对裸 PCM 实时做 1024 点 Q15 定点 DFT、对数分 40 段，配合跨频平滑与峰值保持，柱形稳定且贴底行渲染、不遮图文；",
 "（2）纯硬件 OSD 交互闭环：面板 7 项参数的调节、回显与生效在帧内完成，中文角标随页滑入、曲目倒计时实时刷新，1bit 掩膜逐像素叠加不破坏底图；",
 "（3）帧边界原子切换：四图常驻 SDRAM 四分区，翻页只改分区号并在帧消隐期提交，零加载、无撕裂，响应小于一帧。",
]
anchor = para_by("200字以内（逐点给出）")
for t in inn:
    anchor = add_after(anchor, t)

# 7. 设计流程
anchor = para_by("200字内（可加重要图）")
anchor = add_after(anchor, "作品遵循“需求分析→方案与模块划分→RTL 设计→仿真验证→综合布局布线→时序收敛→上板验证→固化”的工程流程，"
                           "采用小步推进、每项功能独立构建并保留可回退稳定点的方式；最终于 2026 年 10 月 31 日功能冻结并完成 Flash 固化，流程见图 1。")
add_pic_after(anchor, FIG % ("1", "设计流程图"), 14.4, "图1  作品设计流程")

# 8. 第二部分：整体介绍
anchor = para_by("阐述具体的设计细节")
if anchor is not None and anchor.runs:
    anchor.runs[0].text = "系统以安路 EG4S20 FPGA 为核心，由“板载外设 + 片内逻辑”构成，整体框图如图 2 所示。"
    for r in anchor.runs[1:]:
        r._element.getparent().remove(r._element)

anchor = para_by("给出系统整体框图")
if anchor is not None and anchor.runs:
    anchor.runs[0].text = "板载外设包括 TF（MicroSD）卡座、一片 2M×32bit SDRAM、QSPI Flash、HDMI 接口、4 个按键、4 位拨码开关与 8 位数码管；"
    for r in anchor.runs[1:]:
        r._element.getparent().remove(r._element)
anchor = add_pic_after(anchor, FIG % ("2", "系统总体框图"), 14.4, "图2  系统总体框图")
paths = [
 "（1）图片通路：TF 卡 → SD/SPI 控制器 → FAT32 根目录扫描 → 簇链跟随（相对扇区→物理 LBA）→ BMP 解码与等比缩放 → 异步 FIFO → 帧缓存写控制器 → 板载 SDRAM 四分区。",
 "（2）显示通路：视频时序 640×480@60 → 帧读出（帧边界切换）→ 亮度/对比度 → 转场（WIPE/FADE）→ 2 倍商品放大 → 中文角标（1bit 掩膜）→ OSD/频谱柱 → AXIS → HDMI 1.4b 发送。",
 "（3）音频通路：TF 卡裸 PCM 流式播放（BRAM 缓冲）→ 音量增益/TONE 源选择 → I2S 与 ACR → HDMI 音频；增益后 PCM 同时送 1024 点 DFT，结果作为 40 段频谱叠加到显示通路。",
 "（4）控制通路：按键/拨码经消抖与长短按判别后，控制翻页、音量、曲目、快进快退、转场与设置面板；数码管动态扫描显示图号、音量与装载状态。",
]
for t in paths:
    anchor = add_after(anchor, t)

# 9. 2.2.1 硬件整体介绍
h = para_by("2.2.1")
if h is not None and h.runs:
    h.runs[0].text = "2.2.1  硬件整体介绍"
    for r in h.runs[1:]:
        r._element.getparent().remove(r._element)
    a = add_after(h, "硬件平台为 HX4S20C 开发板，核心芯片 EG4S20BG256（19600 个 LUT、4 个 PLL、188 个可用 IO）。板载 50MHz 有源晶振；"
                     "外设包括 TF（MicroSD）卡座、一片 2M×32bit（8MB）SDRAM、QSPI Flash、一个 HDMI 接口（含 DDC）、4 个独立按键、4 位拨码开关与 8 位数码管，USB 5V 供电。"
                     "整机仅需一根 HDMI 线与一张 TF 卡，插入即构成完整播放终端。芯片资源与板载器件见表 2。")
    a = add_table_after(a, "表2  芯片片内资源与板载器件", [
        ("资源 / 器件", "规格 / 数量", "用途"),
        ("LUT", "19600（实用约 9.4k，slices 87.74%）", "全部组合逻辑"),
        ("触发器 REG", "19600（实用约 8.8k）", "全部时序逻辑"),
        ("BRAM9K", "64 块（用 15）", "异步 FIFO、音频缓冲、掩膜 ROM、字库"),
        ("BRAM32K", "16 块（未使用）", "—"),
        ("DSP", "29 个（用 11）", "缩放、DFT、音量增益乘法"),
        ("PLL", "4 个（用 3）", "系统 / 视频 / 音频时钟"),
        ("IO", "188（用 35）", "外部接口"),
        ("板载 SDRAM", "2M×32bit（8MB）", "四分区图片帧缓存"),
        ("QSPI Flash", "板载", "比特流固化、上电自启"),
        ("有源晶振", "50MHz", "系统主时钟源"),
    ])
    add_placeholder(a, "【待补：图3  开发板正面全景，能看清 FPGA 芯片丝印 EG4S20BG256、TF 卡座、SDRAM、数码管、按键与拨码】")
    b = add_placeholder(a, "【待补：图4  TF 卡、HDMI 线、电源线已连接的接口整体照（可不含显示器）】")

# 10. 2.2.2 机械设计
h = para_by("2.2.2")
if h is not None and h.runs:
    h.runs[0].text = "2.2.2  机械设计介绍"
    for r in h.runs[1:]:
        r._element.getparent().remove(r._element)
    a = add_after(h, "本作品基于 HX4S20C 成品开发板实现，为纯电子系统，无机械结构、无运动部件；整机由 FPGA 开发板、一根 HDMI 线和一张 TF 卡组成，"
                     "平放于柜台即可使用，不涉及额外的机械设计。设备摆放形态见图 5。")
    add_placeholder(a, "【待补：图5  设备平放于柜台/桌面的整体摆放形态】")

# 11. 2.2.3 电路各模块
h = para_by("2.2.3")
if h is not None and h.runs:
    h.runs[0].text = "2.2.3  电路各模块介绍"
    for r in h.runs[1:]:
        r._element.getparent().remove(r._element)
    a = add_after(h, "电路按功能分为时钟、TF 卡、板载 SDRAM、HDMI、人机交互五个模块，关键引脚约束见表 3。")
    for t in [
        "（1）时钟：50MHz 晶振经 sys_pll 产生 75MHz（SD 读取）与 125MHz（SDRAM、HDMI 5× 串行）；video_pll 产生 25MHz 像素时钟；audio PLL 产生 12.288MHz 音频 MCLK。",
        "（2）TF 卡接口：工作在 SPI 模式，控制器通过 sd_dclk、sd_mosi、sd_miso、sd_ncs 四线与卡通信，完成扇区读写。",
        "（3）板载 SDRAM 接口：以 125MHz 驱动，32 位数据 dq[31:0]、11 位地址 addr[10:0]、2 位 bank 地址 ba[1:0]、dm0~3 字节掩码与 cke/cs_n/ras_n/cas_n/we_n 控制线，作为四个分区的片外帧缓存。",
        "（4）HDMI 接口：TMDS 三数据通道与一时钟通道以 LVDS 差分输出，每通道经 ODDR 完成 5× 并串；DDC 的 SCL/SDA 在上电时读取一次显示器 EDID。",
        "（5）人机交互：按键、拨码经上拉输入，数码管以段选/位选动态扫描显示。",
    ]:
        a = add_after(a, t)
    a = add_table_after(a, "表3  关键引脚约束（摘录）", [
        ("信号 / 外设", "引脚", "功能"),
        ("clk（50MHz）", "R7", "系统主时钟"),
        ("rst_n", "A2", "全局复位，低有效"),
        ("key1 / key2 / key3", "B2 / C1 / B1", "功能按键"),
        ("sw_con0 / sw_con1", "C6 / C8 / C7", "频谱强调 / 音量预设"),
        ("sd_dclk / mosi / ncs / miso", "A14 / A13 / A12 / B14", "TF 卡 SPI 四线"),
        ("HDMI_CLK_P / D0_P / D1_P / D2_P", "C3 / G5 / F1 / E1", "TMDS 时钟与三数据通道"),
        ("DDC_SCL / DDC_SDA", "P2 / R2", "EDID 读取"),
        ("dq[31:0] / addr[10:0] / ba[1:0]", "S1~S89 / S23~S68 / S69~S70", "板载 SDRAM"),
        ("seg_data / seg_sel", "A5~C16 / E10~F16", "数码管段选 / 位选"),
    ])
    add_placeholder(a, "【待补：图6  HX4S20C 板卡高清特写，能看清 EG4S20BG256 丝印】")
    add_placeholder(a, "【待补：图7  TF 卡座、SDRAM 芯片、HDMI 接口、按键拨码的局部特写】")

# 12. 2.3.1 软件整体
h = para_by("2.3.1")
if h is not None and h.runs:
    h.runs[0].text = "2.3.1  FPGA 逻辑整体介绍"
    for r in h.runs[1:]:
        r._element.getparent().remove(r._element)
    a = add_after(h, "说明：本作品为纯 FPGA 硬件设计，无 CPU、无操作系统，模板所称“软件系统”对应本作品的 FPGA 逻辑设计（RTL 模块与状态机）；"
                     "PC 端仅有菜单图合成、掩膜生成、音频归一化三个离线素材脚本，不参与运行。")
    a = add_after(a, "片内逻辑全部以可综合 Verilog HDL 实现，顶层为 top_tf_hdmi_audio.v，按时钟域划分为控制（50MHz）、存储读取（75MHz）、"
                     "板载 SDRAM 与 HDMI 串行（125MHz）、视频与叠加（25MHz）、音频（12.288MHz）等时钟域。时钟域划分与跨时钟域处理见图 8。")
    a = add_pic_after(a, FIG % ("8", "时钟域"), 14.4, "图8  时钟域划分与跨时钟域处理")

# 13. 2.3.2 软件各模块
h = para_by("2.3.2")
if h is not None and h.runs:
    h.runs[0].text = "2.3.2  FPGA 各逻辑模块设计"
    for r in h.runs[1:]:
        r._element.getparent().remove(r._element)
    a = add_after(h, "显示侧为逐像素叠加管线（图 9）：每像素在 25MHz 下依次经过亮度/对比度、转场、2 倍放大、中文角标、OSD 与频谱叠加，所有切换均在帧消隐边界提交。")
    a = add_pic_after(a, FIG % ("9", "叠加管线"), 14.4, "图9  逐像素显示叠加管线")
    mods = [
     "（1）TF 卡与 FAT32：sd_card_top（spi_master、sd_card_cmd、sd_card_sec_read_write）完成 SPI 物理层与扇区读写；"
     "fat32_volume_scanner 扫描根目录并按文件名定位 PIC1~4.BMP 与 TRACK01~03.RAW；fat32_chain_reader 跟随 FAT 簇链，把相对扇区翻译为物理 LBA，"
     "支持文件碎片化与根目录跨簇；sec_channel_arbiter 对同一扇区通道按优先级仲裁。",
     "（2）BMP 解码与等比缩放（bmp_read）：解析 24bit BMP 头与像素，按目标区域比例计算缩放系数，以定点乘法实现等比缩放与居中偏移，四页画幅不同也能满幅显示、不拉伸；"
     "按目标区域比例计算缩放系数，放大或缩小后居中输出，保证任意分辨率素材都能满幅显示；",
     "（3）四分区帧缓存（resident_switch、frame_read_write、sdr_as_ram）：上电把四张图顺序写入 SDRAM 四个固定分区；显示侧只在帧消隐期切换分区号，零加载、无撕裂；"
     "读、写各经一块异步 FIFO 跨 125/25MHz 时钟域。",
     "（4）音频流式播放（wav_stream_player、track_controller、track_list）：以 BRAM 缓冲从 TF 卡流式读出裸 PCM，扫描曲目并允许编号缺洞，播完自动下一首；"
     "记录簇索引实现 ±10 秒快进快退，seek 后清 FIFO 重灌并同步倒计时；audio_volume_gain 用 Q15 增益实现 16 档（等 2dB）音量，tone_dds 在无曲目时直出测试音；"
     "HDMI 音频侧按 I2S 64fs 组帧，ACR 以 N=6144、CTS 动态测量保证音画同步。",
     "（5）音频频谱（spectrum_engine、spectrum_render）：对增益后 PCM 取 1024 点分块，用 Q15 正余弦表做定点 DFT，按 |I|+|Q| 求幅度、对数分 40 段，"
     "再经跨频 3 点平滑、帧间低通与峰值保持，按固定参考映射为柱高；渲染为屏幕最底行（y=479）的 40 段柱形，每 42 帧刷新。处理流程见图 10。",
    ]
    for t in mods[:4]:
        a = add_after(a, t)
    a = add_after(a, mods[4])
    a = add_pic_after(a, FIG % ("10", "频谱流程"), 14.4, "图10  音频频谱可视化处理流程")
    tail = [
     "（6）中文角标（mask_overlay、mask_slide）：4 页角标掩膜合成 4096×32bit 只读 ROM（txt_all.mif，写使能恒为 0）固化进 BRAM；按坐标窗口叠加 1bit 中文（26px 高），"
     "底板为深棕色块、文字米白；翻页时每帧移动 7px、约 0.48 秒从左侧滑入；放大时隐藏，设置面板打开时保持显示。",
     "（7）转场与放大（video_effect_overlay、video_zoom）：揭幕（WIPE）与黑场淡入淡出（FADE）均在帧边界提交；2 倍双线性放大对相邻 4 像素加权，"
     "放大窗口按页配置（封面不放大），两个按键功能一致，放大过程中翻页自动退出放大。",
     "（8）OSD 与信息条（osd_buffer、osd_renderer、status_bar_render、track_countdown）：中央设置面板列出音量、亮度、对比度、转场、自动轮播、周期、测试音七项，"
     "短按打开、双击关闭、无操作自动关闭；右上显示“歌名 -MM:SS”倒计时，无曲目显示 --:--。",
     "（9）人机交互与跨时钟域（key_longshort、seg_scan、menu_controller）：按键消抖并区分短按、长按与双击；数码管动态扫描显示图号、音量与装载状态。"
     "多 bit 数据一律走异步 FIFO（双时钟 BRAM + 格雷码指针），单 bit 控制走两级寄存器同步，SDC 对异步时钟对设置 set_clock_groups -asynchronous。",
    ]
    for t in tail:
        a = add_after(a, t)

# 14. 第三部分
anchor = para_by("阐述最终实现的成果")
if anchor is not None and anchor.runs:
    anchor.runs[0].text = ("系统已完成全部基础功能与五项扩展功能，比特流固化到 QSPI Flash 后上电即可自动播放："
                           "上电后显示器自动显示菜单页并播放音乐，翻页时中文角标滑入、底部频谱持续跳动。"
                           "下面按整体效果、工程成果与特性成果三部分说明。")
    for r in anchor.runs[1:]:
        r._element.getparent().remove(r._element)

h = para_by("整体介绍（整个系统实物")
if h is not None and h.runs:
    h.runs[0].text = "整体介绍"
    for r in h.runs[1:]:
        r._element.getparent().remove(r._element)
    a = add_after(h, "系统在柜台场景下的整体形态为“开发板 + HDMI 显示器 + TF 卡”，上电后自动进入播放状态，"
                     "无需按键或联网操作；设备平放于台面，正面与斜 45° 全局照片见图 11、图 12。")
    a = add_placeholder(a, "【待补：图11  整机正面：开发板 + HDMI 显示器同框，屏幕显示菜单页与底部频谱】")
    a = add_placeholder(a, "【待补：图12  整机斜 45° 全局照，能看清桌面摆放与连线】")

h = para_by("工程成果")
if h is not None and h.runs:
    h.runs[0].text = "工程成果"
    for r in h.runs[1:]:
        r._element.getparent().remove(r._element)
    add_after(h, "工程成果分机械、电路与逻辑界面三部分：机械部分说明设备形态与摆放方式；"
                 "电路部分给出板卡、接口与固化后的上电自启状态；逻辑界面部分给出各功能的屏幕实测效果。")

h = para_by("3.2.1")
if h is not None and h.runs:
    h.runs[0].text = "3.2.1  机械成果"
    for r in h.runs[1:]:
        r._element.getparent().remove(r._element)
    add_after(h, "如 2.2.2 所述，本作品基于成品开发板，无机械结构与运动部件，设备平放于柜台的形态见图 5。")

h = para_by("3.2.2")
if h is not None and h.runs:
    h.runs[0].text = "3.2.2  电路成果"
    for r in h.runs[1:]:
        r._element.getparent().remove(r._element)
    a = add_after(h, "完成 TF 卡、板载 SDRAM、HDMI、按键、拨码、数码管等全部接口的引脚约束与上板联调；比特流经 QSPI Flash 固化后断电保存、上电自启。板卡、芯片与接口特写见图 13~图 15。")
    add_placeholder(a, "【待补：图13  开发板正面与核心芯片丝印特写】")
    add_placeholder(a, "【待补：图14  TF 卡座、SDRAM 芯片、HDMI 接口、按键拨码局部特写】")
    add_placeholder(a, "【待补：图15  上电后数码管显示（图号/音量/状态）与屏幕正常出画】")

h = para_by("3.2.3")
if h is not None and h.runs:
    h.runs[0].text = "3.2.3  逻辑界面成果"
    for r in h.runs[1:]:
        r._element.getparent().remove(r._element)
    a = add_after(h, "各项显示与交互功能的屏幕实测效果见图 16~图 22。")
    for t in [
      "【待补：图16  四页画面实拍（可拼 2×2 或分四张），体现不同分辨率与两侧黑边】",
      "【待补：图17  左上中文角标特写：普通页 + 设置面板打开时各一张】",
      "【待补：图18  底部 40 段粉色频谱随音乐起伏的实拍】",
      "【待补：图19  中央设置面板（VOLUME/BRIGHT/CONTRAST/TRANS/AUTO/PERIOD/TONE）】",
      "【待补：图20  2 倍放大效果：手冲、卡布、抹茶各一张（对准商品）】",
      "【待补：图21  转场过程：WIPE 与 FADE 各 2~3 帧】",
      "【待补：图22  右上“歌名 -MM:SS”倒计时特写】",
    ]:
        a = add_placeholder(a, t)

h = para_by("特性成果")
if h is not None and h.runs:
    h.runs[0].text = "特性成果"
    for r in h.runs[1:]:
        r._element.getparent().remove(r._element)
    a = add_after(h, "对照赛题要求，基础功能与扩展功能的完成情况见表 4。")
    a = add_table_after(a, "表4  赛题要求完成情况", [
        ("赛题要求", "完成情况", "说明"),
        ("TF 卡读取图片", "已完成", "FAT32 按文件名读取 PIC1~4，支持簇链跟随、碎片化、坏图跳过；不同分辨率图片按比例缩放适配"),
        ("SDRAM 帧缓存", "已完成", "板载 SDRAM 四分区常驻，帧消隐边界切换"),
        ("HDMI 显示与音频", "已完成", "640×480@60 + HDMI 音频（ACR 同步）"),
        ("中文叠加", "已完成", "1bit 掩膜 ROM，左上角标 + 商品卖点，翻页滑入"),
        ("转场", "已完成", "揭幕（WIPE）/ 黑场（FADE）"),
        ("局部放大", "已完成", "2 倍双线性，按页对准商品"),
        ("实时参数调节", "已完成", "音量/亮度/对比度/转场/轮播/周期/测试音 七项"),
        ("音频可视化", "已完成", "1024 点 DFT、40 段频谱贴底渲染"),
        ("离线素材工具", "已完成", "海报→BMP、掩膜生成、音频归一化脚本"),
    ])
    a = add_after(a, "最终固化版本的片内资源占用见表 5，布局布线分时钟域时序见表 6（工具为安路 Tang Dynasty 5.6.2，器件 EG4S20BG256）。")
    a = add_table_after(a, "表5  最终片内资源占用", [
        ("资源", "总量", "实用", "占比"),
        ("slices", "2846", "2497", "87.74%"),
        ("LUT", "19600", "约 9.4k", "—"),
        ("REG", "19600", "约 8.8k", "—"),
        ("BRAM9K", "64", "15", "23.4%"),
        ("BRAM32K", "16", "0", "0%"),
        ("DSP", "29", "11", "37.9%"),
        ("PLL", "4", "3", "75%"),
        ("IO", "188", "35", "18.6%"),
    ])
    a = add_table_after(a, "表6  最终布局布线时序（分时钟域，单位 ns）", [
        ("时钟域", "频率", "建立裕量", "保持裕量", "违例端点"),
        ("sd_card_clk", "75MHz", "+0.320", "+0.014", "0"),
        ("video_clk", "25MHz", "+11.732", "+0.003", "0"),
        ("ext_mem_clk", "125MHz", "+0.933", "+0.021", "0"),
        ("其余六个时钟域", "—", "≥0", "≥0", "0"),
    ])
    a = add_after(a, "稳定性与可靠性验证如下：")
    for t in [
      "（1）上电自启：Flash 固化后断电再上电，自动完成 EDID 读取、TF 卡扫描、四图装载并开始播放，无需人工干预；",
      "（2）翻页零加载：四图常驻后，手动翻页与自动轮播均在帧边界即时生效，无读盘等待与卡顿；",
      "（3）长时间运行：连续轮播与播放音乐，画面无条带、无衰减、频谱不趋直，无死机；",
      "（4）素材更换：更换 TF 卡（不同画幅、不同文案）后上电即可正确适配显示；",
      "（5）交互一致性：音量、亮度、对比度、转场、放大等操作即时生效，OSD 回显正确；",
    ]:
        a = add_after(a, t)

# 15. 第四部分
h = para_by("300字内")
if h is not None and h.runs:
    h.runs[0].text = ("作品仍可从以下方向完善：一是内容容量，当前常驻四页，可在 SDRAM 容量允许下扩展更多分区，或引入外置字库使换文案无需重烧；"
                      "二是音频可视化，可细化频段、加入节拍检测与随节奏变化的配色；三是交互与联网，可加入旋钮、触摸或红外遥控，并预留串口/网络实现远程下发菜单；"
                      "四是编码支持，可由 BMP 扩展到 JPEG/PNG 解码与多语言；五是鲁棒性，可补充看门狗自恢复与素材校验。"
                      "当前图片、音频、交互三条通路相互独立，上述扩展可在不改动整体框架的前提下逐模块叠加。")
    for r in h.runs[1:]:
        r._element.getparent().remove(r._element)

h = para_by("1000字内")
if h is not None and h.runs:
    h.runs[0].text = "本作品从官方样例“能显示一张图”起步，逐步做出一台上电即用的产品化电子菜单，过程中对“纯硬件系统如何组织复杂功能”体会很深。"
    for r in h.runs[1:]:
        r._element.getparent().remove(r._element)
    a = h
    for t in [
      "第一，小步推进、每步可回退。我们把工作拆成几十个小任务，每完成一项就保留一个可上板的稳定点；构建脚本还加了门禁——建立与保持时间不全部达标，就不允许更新交付件。这让问题总能在很小的范围内被定位。",
      "第二，仿真先行。OSD、掩膜、转场都先在仿真中用画帧与黄金值比对边界条件；做放大倍率改造时，正是靠“喂入坐标编码图案、逐像素比对映射”的测试台，才定位到“整行像素必须全部弹出、只取窗口部分”这一关键细节。",
      "第三，时序不只是约束问题，也是资源与架构问题。多画幅、掩膜、频谱叠加逐步加入后，一度出现 4~20 皮秒的保持时间残差；换布局种子、增加修复轮次都无效，最后把占用最高的非关键通路精简掉，占用从 91.8% 降到 88.1%，九个时钟域才真正全部转正。",
      "第四，资源约束会反向塑造设计。BRAM 用满后，频谱幅度改用 |I|+|Q| 的 L1 范数、缩放与混合尽量用移位加法，全片 DSP 只用了 11 个。",
      "第五，产品化细节决定观感：素材要留文字安全区，避免被角标与频谱遮挡；切页要在帧边界提交避免撕裂；角标在设置面板打开时也要可见；换卡、断电重启都要能自动恢复。这些都不在赛题要求里，却决定一台设备能否长期放在柜台上。",
      "最后，纯硬件系统的可靠性来自确定性：没有操作系统，就没有启动等待与崩溃；帧边界切换保证不撕裂；固化后断电再来电即可自动恢复。这让我们理解 FPGA 在低延迟、高可靠场合的价值。",
    ]:
        a = add_after(a, t)

# 16. 参考文献
h = para_by("按照标准格式")
refs = [
 "[1] HDMI Licensing, LLC. HDMI Specification, Version 1.4b[S].",
 "[2] Philips Semiconductors. I2S-bus Specification: Serial digital audio input/output bus[S].",
 "[3] SD Association. SD Physical Layer Simplified Specification[S].",
 "[4] Microsoft Corporation. Microsoft Extensible Firmware Initiative FAT32 File System Specification[S].",
 "[5] VESA. VESA Display Monitor Timing Standard (DMT)[S].",
 "[6] JEDEC Solid State Technology Association. JESD79 Synchronous DRAM Standard[S].",
 "[7] 上海安路信息科技股份有限公司. EG4 系列 FPGA 数据手册[Z].",
 "[8] 上海安路信息科技股份有限公司. Tang Dynasty（TD）软件开发平台用户手册[Z].",
 "[9] 上海安路信息科技股份有限公司. HX4S20C FPGA 开发板用户手册[Z].",
 "[10] R. C. Gonzalez, R. E. Woods. 数字图像处理[M].",
 "[11] A. V. Oppenheim, R. W. Schafer. 离散时间信号处理[M].",
 "[12] 夏宇闻. Verilog 数字系统设计教程[M].",
]
if h is not None and h.runs:
    h.runs[0].text = refs[0]
    for r in h.runs[1:]:
        r._element.getparent().remove(r._element)
    a = h
    for t in refs[1:]:
        a = add_after(a, t, indent=False)

# ================== 后处理：删除模板提示语、修正副标题颜色 ==================
import re as _re
HINT = _re.compile(r'^(\d+\s*字(以内)?|给出系统整体框图|阐述具体|阐述最终|（不要出现|按照标准格式|整体介绍（|工程成果（|特性成果（)')
removed = 0
for p in list(doc.paragraphs):
    tt = p.text.strip()
    if HINT.match(tt):
        print("  删除提示语:", tt[:40])
        p._p.getparent().remove(p._p)
        removed += 1
print("已删除模板提示语段落:", removed)

# 副标题改黑色
for p in doc.paragraphs:
    if p.text.strip().startswith("——基于安路"):
        for r in p.runs:
            r.font.color.rgb = RGBColor(0x33, 0x33, 0x33)
        break

# ================== 后处理：统一缩进（只处理新插入的段落） ==================
import re as _re2
fixed = 0
for p in doc.paragraphs:
    if id(p._p) in TPL_IDS:
        continue
    tt = p.text.strip()
    if not tt:
        continue
    pf = p.paragraph_format
    pf.left_indent = Pt(0)
    if _re2.match(r'^\[\d+\]', tt):
        pf.first_line_indent = Pt(0)          # 参考文献：顶格，回行不缩进
    elif tt.startswith("【待补") or _re2.match(r'^(图|表)\s?\d+', tt):
        pf.first_line_indent = Pt(0)
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    else:
        pf.first_line_indent = Pt(24)         # 正文/条目：首行缩进 2 字符
    fixed += 1

# ---- 标题与图片的“与下段同页” ----
HEADS = ("功能与特性", "应用领域", "主要技术特点", "主要性能指标", "主要创新点", "设计流程",
         "整体介绍", "硬件系统介绍", "软件系统介绍", "工程成果", "特性成果",
         "可扩展之处", "心得体会", "2.2.1", "2.2.2", "2.2.3", "2.3.1", "2.3.2",
         "3.2.1", "3.2.2", "3.2.3", "第一部分", "第二部分", "第三部分", "第四部分", "第五部分")
kept = 0
for p in doc.paragraphs:
    tt = p.text.strip()
    if tt.startswith(HEADS):
        p.paragraph_format.keep_with_next = True
        kept += 1
    if p._p.findall(".//{http://schemas.openxmlformats.org/drawingml/2006/main}blip"):
        p.paragraph_format.keep_with_next = True   # 图片与题注同页
        kept += 1
print("设置与下段同页:", kept)

print("缩进归一化段落数:", fixed)

doc.save(OUT)
print("已生成（模板基底）:", OUT)
print("段落数:", len(doc.paragraphs), " 表格数:", len(doc.tables))
