# -*- coding: utf-8 -*-
"""
按官方《技术报告模板》生成技术报告（docx + md 双份）。
内容与当前定稿固件 614270A8 对齐；实物照片/截图一律留占位符。
"""
import io, os
from docx import Document
from docx.shared import Pt, Cm, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn

OUT_DIR = r"D:\AAA_University\Anlu\Project\doc\报告"
DOCX = os.path.join(OUT_DIR, "技术报告_木与豆咖啡_v1.docx")
MD = os.path.join(OUT_DIR, "技术报告_木与豆咖啡_v1.md")

TITLE = "木与豆咖啡 · 店内音乐电子菜单"
SUB = "——基于安路 EG4S20 的单 FPGA 店内音乐电子菜单"

# ============ 内容（唯一真源） ============
# 块类型: h1/h2/h3/p/li/table/ph (占位图)/note
BLOCKS = []
def h1(t): BLOCKS.append(("h1", t))
def h2(t): BLOCKS.append(("h2", t))
def h3(t): BLOCKS.append(("h3", t))
def p(t):  BLOCKS.append(("p", t))
def li(t): BLOCKS.append(("li", t))
def ph(t): BLOCKS.append(("ph", t))
def note(t): BLOCKS.append(("note", t))
def table(title, rows): BLOCKS.append(("table", (title, rows)))

# ---------- 标题 ----------
h1(TITLE)
p(SUB)

# ---------- 摘要 ----------
h2("摘要")
p("本作品是一台置于咖啡店柜台的电子菜单板，面向数字广告牌与商业展陈终端场景，"
  "是 2026 全国大学生嵌入式芯片与系统设计竞赛 FPGA 创新设计赛道（安路赛道）选题一的完整实现。"
  "整机只有一颗安路 EG4S20 FPGA，无处理器、无操作系统：从 TF 卡读取、图像缩放、图层叠加到 HDMI 输出"
  "全部由硬件逻辑完成，上电即自动轮播四页商品海报并播放背景音乐，底部频谱随音乐起伏。")
p("上电后 FPGA 扫描 FAT32 格式 TF 卡，将四张不同画幅的商品海报（1280×960 4:3、1280×960 4:3、"
  "1280×720 16:9、1024×1024 1:1）解码后按比例适配到 640×480 输出，居中并自动补黑边，"
  "常驻板载 2M×32bit SDRAM 的四个分区；翻页只改分区号，在帧消隐边界切换，零加载、无撕裂。"
  "48kHz 音乐以裸 PCM 流式读出，经 HDMI 与画面同步播放；曲目切换、快进快退、音量、亮度、对比度"
  "均可用板载按键与拨码完成，并在 OSD 上回显。")
p("在满足赛题基础要求之外，作品实现了中文叠加、转场、局部放大、实时参数调节与音频可视化五项扩展："
  "商品名与卖点以 1bit 掩膜由 FPGA 逐像素叠加，左上角中文角标随翻页滑入并在设置面板打开时依然显示；"
  "支持揭幕与黑场两种转场；支持 2 倍双线性局部放大且放大窗口按页对准商品；"
  "对 PCM 实时做 1024 点定点 DFT，按对数分为 40 段频谱贴底部渲染。")
p("最终版本资源占用为 slices 87.74%、BRAM9K 15/64、DSP 11/29；布局布线后九个时钟域"
  "建立与保持时间全部无违例（显示主通路建立裕量 +11.73ns）。比特流已固化至 QSPI Flash，"
  "断电重启后自动运行、无需 PC，换卡即换菜单。")

# ---------- 第一部分 ----------
h2("第一部分  作品概述")
h3("功能与特性")
li("（1）多画幅自适应播放：识别 FAT32 根目录 PIC1~PIC4.BMP，四页分别为 4:3、4:3、16:9、1:1，"
   "按比例适配 640×480 并自动补黑边，手动翻页或自动轮播；")
li("（2）背景音乐：48kHz 裸 PCM 经 HDMI 与画面同步播放，支持 16 档音量、曲目切换与 ±10 秒快进快退；")
li("（3）中文叠加：左上角中文角标（每页不同文案）与商品卖点以 1bit 掩膜由 FPGA 叠加，翻页时滑入，"
   "设置面板打开时仍正常显示；")
li("（4）转场与放大：揭幕、黑场两种转场；2 倍双线性放大，放大窗口按页对准商品，封面不放大；")
li("（5）实时调节与可视化：亮度、对比度、音量实时可调并在 OSD 回显；40 段频谱贴屏幕最底行随音乐起伏；")
li("（6）可靠性：四分区常驻、切图零加载；比特流固化 Flash，上电自启、长期无人值守运行。")

h3("应用领域")
p("作品定位为门店菜单板、数字广告牌与商业展陈终端，典型场景是咖啡店、烘焙店、甜品店的柜台："
  "设备上电即播，无需电脑、手机或联网；店员换菜单只需换 TF 卡内容，无需专业维护；"
  "四页图文循环展示，背景音乐与频谱营造氛围，亮度、对比度、音量可在现场即时调整。")
p("其平台化硬件底座可推广到更多场景：餐厅与奶茶店的点餐价格屏、门店与展台广告欢迎屏、"
  "酒店楼宇信息发布屏、教室与会议室展示终端。图片（FAT32→BMP→帧缓存→HDMI）、"
  "音频（PCM→DFT→HDMI）、交互（按键/拨码/OSD）三条通路相互独立，可分别复用为电子相册、"
  "音频可视化装置与信息发布终端，也是 FPGA 课程中“图像+音频+存储+高速接口”的综合实验载体。")

h3("主要技术特点")
li("（1）纯硬件、无操作系统：全部功能由 FPGA 逻辑实现，无外部 CPU 与软件，状态确定、上电即播；")
li("（2）四分区常驻零加载：四张图上电后常驻 SDRAM 四个分区，翻页只改分区号，"
   "在帧消隐边界原子生效，无加载等待、无撕裂；")
li("（3）真实 DFT 频谱：对增益后 PCM 实时做 1024 点 Q15 定点 DFT、对数分 40 段，"
   "配合跨频平滑、峰值保持与固定参考映射，柱形稳定不抖；")
li("（4）位图掩膜叠加：4 页中文角标掩膜合成 4096×32bit 只读 ROM 固化进 BRAM，"
   "文字与底图分层、逐像素叠加，随翻页滑入；")
li("（5）多画幅自适应：按页读取各图的原始宽高，等比缩放并计算居中偏移，"
   "四页画幅不同也能满幅显示且不拉伸；")
li("（6）规范多时钟域：50/75/125/25/12.288MHz 多域之间，多 bit 数据走异步 FIFO、"
   "单 bit 控制两级同步，SDC 约束完整，最终九个时钟域建立与保持时间零违例。")

h3("主要性能指标")
p("主要性能指标见表 1，资源与时序数据取自最终固化版本的安路 TD（Tang Dynasty 5.6.2）"
  "综合与布局布线报告。")
table("表1  主要性能指标", [
    ("项目", "指标 / 说明"),
    ("显示 / 刷新率", "640×480@60Hz（VIC=1），像素时钟 25MHz"),
    ("视频接口", "HDMI 1.4b，TMDS 3 数据 + 1 时钟，10bit 串行"),
    ("音频", "48kHz、16bit 单声道，HDMI 音频包，ACR 同步（N=6144）"),
    ("菜单页面", "4 页：1280×960(4:3)、1280×960(4:3)、1280×720(16:9)、1024×1024(1:1)，自动补黑边"),
    ("帧缓存", "板载 SDRAM 2M×32bit（8MB），四分区常驻"),
    ("中文角标", "1bit 掩膜 ROM 4096×32bit，每条 26px 高，翻页滑入"),
    ("音频频谱", "1024 点 DFT，40 段对数分箱，贴最底行渲染"),
    ("资源占用", "slices 87.74%，BRAM9K 15/64，DSP 11/29"),
    ("时序", "九个时钟域 setup/hold 全部 0 违例"),
    ("启动方式", "QSPI Flash 固化，上电自启，无需 PC"),
])

h3("主要创新点")
li("（1）多画幅自适应：四页画幅各异，装载时按页记录宽高与居中偏移，显示按分区取几何，"
   "同一固件混放不同比例素材且不拉伸；")
li("（2）真实 DFT 频谱：裸 PCM 实时 1024 点 Q15 DFT、对数分 40 段，经平滑与峰值保持，"
   "贴屏幕最底行渲染、不遮图文；")
li("（3）帧边界原子切换：四页常驻 SDRAM，翻页只改分区号并在消隐期生效，零加载无撕裂，"
   "角标随页滑入。")

h3("设计流程")
p("作品遵循“需求分析→方案与模块划分→RTL 设计→仿真验证→综合布局布线→时序收敛→上板验证→固化”"
  "的工程流程，采用小步推进、每项功能独立构建并保留可回退稳定点的方式；"
  "仿真以画帧与黄金值比对先行，上板逐项验证，最终于 2026 年 10 月 31 日功能冻结并完成 Flash 固化，"
  "流程见图 1。")
ph("图1  作品设计流程")
ph("【待补：图1  设计流程图（可用“需求→方案→RTL→仿真→时序→上板→固化”七步流程框图）】")

# ---------- 第二部分 ----------
h2("第二部分  系统组成及功能说明")
h3("整体介绍")
p("系统以安路 EG4S20 FPGA 为核心，由“板载外设 + 片内逻辑”构成，总体框图见图 2。"
  "板载外设包括：TF（MicroSD）卡座、一片 2M×32bit SDRAM、QSPI Flash、HDMI 接口、"
  "4 个按键、4 位拨码开关与 8 位数码管；外部只需一根 HDMI 线接显示器、插入存有素材的 TF 卡。"
  "片内逻辑按数据流向分为图片、显示、音频、控制四条通路。")
li("（1）图片通路：TF 卡 → SD/SPI 控制器 → FAT32 根目录扫描 → 簇链跟随（相对扇区→物理 LBA）→ "
   "BMP 解码与等比缩放 → 异步 FIFO → 帧缓存写控制器 → 板载 SDRAM 四分区。")
li("（2）显示通路：视频时序 640×480@60 → 帧读出（帧边界切换）→ 亮度/对比度 → 转场（WIPE/FADE）→ "
   "2 倍商品放大 → 中文角标（1bit 掩膜）→ OSD/频谱柱 → AXIS → HDMI 1.4b 发送。")
li("（3）音频通路：TF 卡裸 PCM 流式播放（BRAM 缓冲）→ 音量增益/TONE 源选择 → I2S 与 ACR → HDMI 音频；"
   "增益后 PCM 同时送 1024 点 DFT，结果作为 40 段频谱叠加到显示通路。")
li("（4）控制通路：按键/拨码经消抖与长短按判别后，控制翻页、音量、曲目、快进快退、转场与设置面板；"
   "数码管动态扫描显示图号、音量与装载状态。")

h3("硬件系统介绍")
h3("2.2.1  硬件整体介绍")
p("硬件平台为 HX4S20C 开发板，核心芯片 EG4S20BG256（19600 个 LUT、4 个 PLL、188 个可用 IO）。"
  "板载 50MHz 有源晶振；外设包括 TF（MicroSD）卡座、一片 2M×32bit（8MB）SDRAM、QSPI Flash、"
  "一个 HDMI 接口（含 DDC）、4 个独立按键、4 位拨码开关与 8 位数码管，USB 5V 供电。"
  "整机仅需一根 HDMI 线与一张 TF 卡，插入即构成完整播放终端。芯片资源与板载器件见表 2。")
table("表2  芯片片内资源与板载器件", [
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
ph("图3  系统硬件整体（开发板正面）")
ph("图4  系统硬件整体（接口与连接）")
ph("【待补：图3  开发板正面全景，能看清 FPGA 芯片丝印 EG4S20BG256、TF 卡座、SDRAM、数码管、按键与拨码】")
ph("【待补：图4  TF 卡、HDMI 线、电源线已连接的接口整体照（可不含显示器）】")

h3("2.2.2  机械设计介绍")
p("本作品基于 HX4S20C 成品开发板实现，为纯电子系统，无机械结构、无运动部件；"
  "整机由 FPGA 开发板、一根 HDMI 线和一张 TF 卡组成，平放于柜台即可使用，不涉及额外的机械设计。"
  "设备摆放形态见图 5。")
ph("图5  设备柜台摆放形态")
ph("【待补：图5  设备平放于柜台/桌面的整体摆放形态】")

h3("2.2.3  电路各模块介绍")
p("电路按功能分为时钟、TF 卡、板载 SDRAM、HDMI、人机交互五个模块，关键引脚约束见表 3。")
li("（1）时钟：50MHz 晶振经 sys_pll 产生 75MHz（SD 读取）与 125MHz（SDRAM、HDMI 5× 串行）；"
   "video_pll 产生 25MHz 像素时钟；audio PLL 产生 12.288MHz 音频 MCLK。")
li("（2）TF 卡接口：工作在 SPI 模式，控制器通过 sd_dclk、sd_mosi、sd_miso、sd_ncs 四线与卡通信，"
   "完成扇区读写。")
li("（3）板载 SDRAM 接口：以 125MHz 驱动，32 位数据 dq[31:0]、11 位地址 addr[10:0]、"
   "2 位 bank 地址 ba[1:0]、dm0~3 字节掩码与 cke/cs_n/ras_n/cas_n/we_n 控制线，作为四个分区的片外帧缓存。")
li("（4）HDMI 接口：TMDS 三数据通道与一时钟通道以 LVDS 差分输出，每通道经 ODDR 完成 5× 并串；"
   "DDC 的 SCL/SDA 在上电时读取一次显示器 EDID。")
li("（5）人机交互：按键、拨码经上拉输入，数码管以段选/位选动态扫描显示。")
table("表3  关键引脚约束（摘录）", [
    ("信号 / 外设", "引脚", "功能"),
    ("clk（50MHz）", "R7", "系统主时钟"),
    ("rst_n", "A2", "全局复位，低有效"),
    ("key1 / key2 / key3", "B2 / C1 / B1", "功能按键"),
    ("sw_con0 / sw_con1", "C8 / C7", "频谱强调 / 音量预设"),
    ("sw_key_mode / sw_transition", "C6 / C5", "切歌切图模式 / 频谱强调"),
    ("sd_dclk / mosi / ncs / miso", "A14 / A13 / A12 / B14", "TF 卡 SPI 四线"),
    ("HDMI_CLK_P / D0_P / D1_P / D2_P", "C3 / G5 / F1 / E1", "TMDS 时钟与三数据通道"),
    ("DDC_SCL / DDC_SDA", "P2 / R2", "EDID 读取"),
    ("dq[31:0] / addr[10:0] / ba[1:0]", "S1~S89 / S23~S68 / S69~S70", "板载 SDRAM"),
    ("seg_data / seg_sel", "A5~C16 / E10~F16", "数码管段选 / 位选"),
])
ph("图6  FPGA 开发板与核心芯片特写")
ph("图7  TF 卡座 / SDRAM / HDMI 接口特写")
ph("【待补：图6  HX4S20C 板卡高清特写，能看清 EG4S20BG256 丝印】")
ph("【待补：图7  TF 卡座、SDRAM 芯片、HDMI 接口、按键拨码的局部特写】")

h3("软件系统介绍")
h3("2.3.1  FPGA 逻辑整体介绍")
p("说明：本作品为纯 FPGA 硬件设计，无 CPU、无操作系统，模板所称“软件系统”对应本作品的 FPGA 逻辑设计"
  "（RTL 模块与状态机）；PC 端仅有菜单图合成、掩膜生成、音频归一化三个离线素材脚本，不参与运行。")
p("片内逻辑全部以可综合 Verilog HDL 实现，顶层为 top_tf_hdmi_audio.v，按时钟域划分为"
  "控制（50MHz）、存储读取（75MHz）、板载 SDRAM 与 HDMI 串行（125MHz）、视频与叠加（25MHz）、"
  "音频（12.288MHz）等时钟域。时钟域划分与跨时钟域处理见图 8。")
ph("图8  时钟域划分与跨时钟域处理")
ph("【待补：图8  时钟域框图（我方绘制，可用“输入时钟→PLL→各域→CDC 方式”示意）】")

h3("2.3.2  FPGA 各逻辑模块设计")
p("显示侧为逐像素叠加管线（图 9）：每像素在 25MHz 下依次经过亮度/对比度、转场、2 倍放大、"
  "中文角标、OSD 与频谱叠加，所有切换均在帧消隐边界提交。")
ph("图9  逐像素显示叠加管线")
ph("【待补：图9  叠加管线框图（我方绘制）】")
li("（1）TF 卡与 FAT32：sd_card_top（spi_master、sd_card_cmd、sd_card_sec_read_write）完成 SPI 物理层"
   "与扇区读写；fat32_volume_scanner 扫描根目录并按文件名定位 PIC1~4.BMP 与 TRACK01~03.RAW；"
   "fat32_chain_reader 跟随 FAT 簇链，把相对扇区翻译为物理 LBA，支持文件碎片化与根目录跨簇；"
   "sec_channel_arbiter 对同一扇区通道按优先级仲裁。")
li("（2）BMP 解码与等比缩放（bmp_read）：解析 24bit BMP 头与像素，按目标区域比例计算缩放系数，"
   "以定点乘法实现等比缩放与居中偏移，四页画幅不同也能满幅显示、不拉伸；"
   "按素材规格要求（宽高均不小于 640×480），小图放大通路已从设计中移除。")
li("（3）四分区帧缓存（resident_switch、frame_read_write、sdr_as_ram）：上电把四张图顺序写入"
   "SDRAM 四个固定分区；显示侧只在帧消隐期切换分区号，零加载、无撕裂；读、写各经一块异步 FIFO "
   "跨 125/25MHz 时钟域。")
li("（4）音频流式播放（wav_stream_player、track_controller、track_list）：以 BRAM 缓冲从 TF 卡流式读出裸 PCM，"
   "扫描曲目并允许编号缺洞，播完自动下一首；记录簇索引实现 ±10 秒快进快退，seek 后清 FIFO 重灌并同步倒计时；"
   "audio_volume_gain 用 Q15 增益实现 16 档（等 2dB）音量，tone_dds 在无曲目时直出测试音；"
   "HDMI 音频侧按 I2S 64fs 组帧，ACR 以 N=6144、CTS 动态测量保证音画同步。")
li("（5）音频频谱（spectrum_engine、spectrum_render）：对增益后 PCM 取 1024 点分块，用 Q15 正余弦表做定点 DFT，"
   "按 |I|+|Q| 求幅度、对数分 40 段，再经跨频 3 点平滑、帧间低通与峰值保持，按固定参考映射为柱高；"
   "渲染为屏幕最底行（y=479）的 40 段柱形，每 42 帧刷新。处理流程见图 10。")
ph("图10  音频频谱可视化处理流程")
ph("【待补：图10  频谱处理流程图（我方绘制：采样→窗→DFT→|I|+|Q|→对数分箱→平滑→渲染）】")
li("（6）中文角标（mask_overlay、mask_slide）：4 页角标掩膜合成 4096×32bit 只读 ROM（txt_all.mif，"
   "写使能恒为 0）固化进 BRAM；按坐标窗口叠加 1bit 中文（26px 高），底板为深棕色块、文字米白；"
   "翻页时每帧移动 7px、约 0.48 秒从左侧滑入；设置在放大时隐藏，菜单打开时保持显示。")
li("（7）转场与放大（video_effect_overlay、video_zoom）：揭幕（WIPE）与黑场淡入淡出（FADE）均在帧边界提交；"
   "2 倍双线性放大对相邻 4 像素加权，放大窗口按页配置（封面不放大），两个按键功能一致，"
   "放大过程中翻页自动退出放大。")
li("（8）OSD 与信息条（osd_buffer、osd_renderer、status_bar_render、track_countdown）：中央设置面板列出"
   "音量、亮度、对比度、转场、自动轮播、周期、测试音七项，短按打开、双击关闭、无操作自动关闭；"
   "右上显示“歌名 -MM:SS”倒计时，无曲目显示 --:--。")
li("（9）人机交互与跨时钟域（key_longshort、seg_scan、menu_controller）：按键消抖并区分短按、长按与双击；"
   "数码管动态扫描显示图号、音量与装载状态。多 bit 数据一律走异步 FIFO（双时钟 BRAM + 格雷码指针），"
   "单 bit 控制走两级寄存器同步，SDC 对异步时钟对设置 set_clock_groups -asynchronous。")

# ---------- 第三部分 ----------
h2("第三部分  完成情况及性能参数")
h3("整体介绍")
p("系统已完成全部基础功能与五项扩展功能，比特流固化到 QSPI Flash 后上电即可自动播放。"
  "上电后显示器自动显示菜单页并播放音乐，翻页时中文角标滑入、频谱持续跳动。"
  "整机正面与斜 45° 全局照片见图 11、图 12。")
ph("图11  整机实物正面")
ph("图12  整机实物斜 45° 全局")
ph("【待补：图11  整机正面：开发板 + HDMI 显示器同框，屏幕显示菜单页与底部频谱】")
ph("【待补：图12  整机斜 45° 全局照，能看清桌面摆放与连线】")

h3("工程成果")
h3("3.2.1  机械成果")
p("如 2.2.2 所述，本作品基于成品开发板，无机械结构与运动部件，设备平放于柜台的形态见图 5。")

h3("3.2.2  电路成果")
p("完成 TF 卡、板载 SDRAM、HDMI、按键、拨码、数码管等全部接口的引脚约束与上板联调；"
  "比特流经 QSPI Flash 固化后断电保存、上电自启。板卡、芯片与接口特写见图 13~图 15。")
ph("图13  开发板与核心芯片特写")
ph("图14  接口局部特写")
ph("图15  上电自启与数码管显示")
ph("【待补：图13  开发板正面与核心芯片丝印特写】")
ph("【待补：图14  TF 卡座、SDRAM 芯片、HDMI 接口、按键拨码局部特写】")
ph("【待补：图15  上电后数码管显示（图号/音量/状态）与屏幕正常出画】")

h3("3.2.3  逻辑界面成果")
p("各项显示与交互功能的屏幕实测效果见图 16~图 22。")
ph("图16  四页海报（4:3 / 4:3 / 16:9 / 1:1）")
ph("图17  左上中文角标（含设置面板打开时）")
ph("图18  40 段音频频谱")
ph("图19  中央设置面板 OSD")
ph("图20  2 倍商品放大（手冲 / 卡布 / 抹茶）")
ph("图21  转场特效（WIPE / FADE）")
ph("图22  右上歌名与曲目倒计时")
ph("【待补：图16  四页屏幕实拍（可拼 2×2 或分四张），体现不同画幅与黑边】")
ph("【待补：图17  左上中文角标特写：正常页 + 设置面板打开时各一张】")
ph("【待补：图18  底部 40 段粉色频谱随音乐起伏的实拍】")
ph("【待补：图19  中央设置面板（VOLUME/BRIGHT/CONTRAST/TRANS/AUTO/PERIOD/TONE）】")
ph("【待补：图20  2 倍放大效果：手冲、卡布、抹茶各一张（对准商品）】")
ph("【待补：图21  转场过程：WIPE 与 FADE 各 2~3 帧】")
ph("【待补：图22  右上“歌名 -MM:SS”倒计时特写】")

h3("特性成果")
p("对照赛题要求，基础功能与扩展功能的完成情况见表 4。")
table("表4  赛题要求完成情况", [
    ("赛题要求", "完成情况", "说明"),
    ("TF 卡读取图片", "已完成", "FAT32 按文件名读取 PIC1~4，支持簇链跟随、碎片化、坏图跳过"),
    ("SDRAM 帧缓存", "已完成", "板载 SDRAM 四分区常驻，帧消隐边界切换"),
    ("HDMI 显示与音频", "已完成", "640×480@60 + HDMI 音频（ACR 同步）"),
    ("中文叠加", "已完成", "1bit 掩膜 ROM，左上角标 + 商品卖点，翻页滑入"),
    ("转场", "已完成", "揭幕（WIPE）/ 黑场（FADE）"),
    ("局部放大", "已完成", "2 倍双线性，按页对准商品"),
    ("实时参数调节", "已完成", "音量/亮度/对比度/转场/轮播/周期/测试音 七项"),
    ("音频可视化", "已完成", "1024 点 DFT、40 段频谱贴底渲染"),
    ("离线素材工具", "已完成", "海报→BMP、掩膜生成、音频归一化脚本"),
])
p("最终固化版本的片内资源占用见表 5，布局布线分时钟域时序见表 6"
  "（工具为安路 Tang Dynasty 5.6.2，器件 EG4S20BG256）。")
table("表5  最终片内资源占用", [
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
table("表6  最终布局布线时序（分时钟域，单位 ns）", [
    ("时钟域", "频率", "建立裕量（WNS）", "保持裕量（WNS）", "违例端点"),
    ("sd_card_clk", "75MHz", "+0.320", "+0.014", "0"),
    ("video_clk", "25MHz", "+11.732", "+0.003", "0"),
    ("ext_mem_clk", "125MHz", "+0.933", "+0.021", "0"),
    ("其余六个时钟域", "—", "≥0", "≥0", "0"),
])
p("稳定性与可靠性验证如下：")
li("（1）上电自启：Flash 固化后断电再上电，自动完成 EDID 读取、TF 卡扫描、四图装载并开始播放，无需人工干预；")
li("（2）翻页零加载：四图常驻后，手动翻页与自动轮播均在帧边界即时生效，无读盘等待与卡顿；")
li("（3）长时间运行：连续轮播与播放音乐，画面无条带、无衰减、频谱不趋直，无死机；")
li("（4）素材更换：更换 TF 卡（不同画幅、不同文案）后上电即可正确适配显示；")
li("（5）交互一致性：音量、亮度、对比度、转场、放大等操作即时生效，OSD 回显正确。")

# ---------- 第四部分 ----------
h2("第四部分  总结")
h3("可扩展之处")
p("作品仍可从以下方向完善：一是内容容量，当前常驻四页，可在 SDRAM 容量允许下扩展更多分区，"
  "或引入外置字库使换文案无需重烧；二是音频可视化，可细化频段、加入节拍检测与随节奏变化的配色；"
  "三是交互与联网，可加入旋钮、触摸或红外遥控，并预留串口/网络实现远程下发菜单；"
  "四是编码支持，可由 BMP 扩展到 JPEG/PNG 解码与多语言；五是鲁棒性，可补充看门狗自恢复与素材校验。"
  "当前图片、音频、交互三条通路相互独立，上述扩展可在不改动整体框架的前提下逐模块叠加。")

h3("心得体会")
p("本作品从官方样例“能显示一张图”起步，逐步做出一台上电即用的产品化电子菜单，"
  "过程中对“纯硬件系统如何组织复杂功能”体会很深。")
p("第一，小步推进、每步可回退。我们把工作拆成几十个小任务，每完成一项就保留一个可上板的稳定点；"
  "构建脚本还加了门禁——建立与保持时间不全部达标，就不允许更新交付件。这让问题总能在很小的范围内被定位。")
p("第二，仿真先行。OSD、掩膜、转场都先在仿真中用画帧与黄金值比对边界条件；做放大倍率改造时，"
  "正是靠“喂入坐标编码图案、逐像素比对映射”的测试台，才定位到“整行像素必须全部弹出、只取窗口部分”这一关键细节。")
p("第三，时序不只是约束问题，也是资源与架构问题。多画幅、掩膜、频谱叠加逐步加入后，"
  "一度出现 4~20 皮秒的保持时间残差；换布局种子、增加修复轮次都无效，"
  "最后按素材规格移除用不到的小图放大通路，占用从 91.8% 降到 88.1%，九个时钟域才真正全部转正。")
p("第四，资源约束会反向塑造设计。BRAM 用满后，频谱幅度改用 |I|+|Q| 的 L1 范数、缩放与混合尽量用移位加法，"
  "全片 DSP 只用了 11 个。")
p("第五，产品化细节决定观感：素材要留文字安全区，避免被角标与频谱遮挡；切页要在帧边界提交避免撕裂；"
  "角标在设置面板打开时也要可见；换卡、断电重启都要能自动恢复。这些都不在赛题要求里，"
  "却决定一台设备能否长期放在柜台上。")
p("最后，纯硬件系统的可靠性来自确定性：没有操作系统，就没有启动等待与崩溃；帧边界切换保证不撕裂；"
  "固化后断电再来电即可自动恢复。这让我们理解 FPGA 在低延迟、高可靠场合的价值。")
# ---------- 第五部分 ----------
h2("第五部分  参考文献")
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
    "[10] R. C. Gonzalez, R. E. Woods. 数字图像处理（Digital Image Processing）[M].",
    "[11] A. V. Oppenheim, R. W. Schafer. 离散时间信号处理（Discrete-Time Signal Processing）[M].",
    "[12] 夏宇闻. Verilog 数字系统设计教程[M].",
]
for r in refs:
    p(r)

# ============ 生成 docx ============
def set_cn_font(run, name="微软雅黑", size=None, bold=False, color=None):
    run.font.name = name
    run._element.rPr.rFonts.set(qn("w:eastAsia"), name)
    if size: run.font.size = Pt(size)
    run.font.bold = bold
    if color: run.font.color.rgb = color


doc = Document()
sec = doc.sections[0]
sec.page_width, sec.page_height = Cm(21), Cm(29.7)
sec.left_margin = sec.right_margin = Cm(2.6)
sec.top_margin = sec.bottom_margin = Cm(2.4)

# 正文默认样式
st = doc.styles["Normal"]
st.font.name = "微软雅黑"
st.element.rPr.rFonts.set(qn("w:eastAsia"), "微软雅黑")
st.font.size = Pt(10.5)
st.paragraph_format.line_spacing = 1.5
st.paragraph_format.space_after = Pt(4)

FIRST_H1 = True
for kind, val in BLOCKS:
    if kind == "h1":
        para = doc.add_paragraph()
        para.alignment = WD_ALIGN_PARAGRAPH.CENTER
        r = para.add_run(val)
        set_cn_font(r, size=20, bold=True)
        para.paragraph_format.space_before = Pt(6)
        para.paragraph_format.space_after = Pt(6)
    elif kind == "h2":
        para = doc.add_paragraph()
        r = para.add_run(val)
        set_cn_font(r, size=14, bold=True, color=RGBColor(0x1F, 0x3B, 0x64))
        para.paragraph_format.space_before = Pt(12)
        para.paragraph_format.space_after = Pt(6)
    elif kind == "h3":
        para = doc.add_paragraph()
        r = para.add_run(val)
        set_cn_font(r, size=12, bold=True, color=RGBColor(0x2E, 0x4E, 0x7E))
        para.paragraph_format.space_before = Pt(8)
        para.paragraph_format.space_after = Pt(4)
    elif kind == "p":
        para = doc.add_paragraph()
        para.paragraph_format.first_line_indent = Pt(21)
        r = para.add_run(val)
        set_cn_font(r, size=10.5)
    elif kind == "li":
        para = doc.add_paragraph()
        para.paragraph_format.left_indent = Pt(12)
        r = para.add_run(val)
        set_cn_font(r, size=10.5)
    elif kind == "note":
        para = doc.add_paragraph()
        r = para.add_run(val)
        set_cn_font(r, size=9, color=RGBColor(0x80, 0x80, 0x80))
    elif kind == "ph":
        is_caption = val.startswith("图") or val.startswith("表")
        para = doc.add_paragraph()
        para.alignment = WD_ALIGN_PARAGRAPH.CENTER
        r = para.add_run(val)
        if is_caption:
            set_cn_font(r, size=10, bold=False, color=RGBColor(0x33, 0x33, 0x33))
        else:
            set_cn_font(r, size=10, bold=True, color=RGBColor(0xC0, 0x00, 0x00))
        para.paragraph_format.space_before = Pt(6)
        para.paragraph_format.space_after = Pt(2)
    elif kind == "table":
        title, rows = val
        cap = doc.add_paragraph()
        cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
        r = cap.add_run(title)
        set_cn_font(r, size=10, bold=True, color=RGBColor(0x33, 0x33, 0x33))
        cap.paragraph_format.space_before = Pt(6)
        t = doc.add_table(rows=len(rows), cols=len(rows[0]))
        t.style = "Table Grid"
        t.alignment = WD_TABLE_ALIGNMENT.CENTER
        for i, row in enumerate(rows):
            for j, cell in enumerate(row):
                c = t.cell(i, j)
                c.text = ""
                para = c.paragraphs[0]
                rr = para.add_run(cell)
                set_cn_font(rr, size=9.5, bold=(i == 0))
                para.alignment = WD_ALIGN_PARAGRAPH.CENTER if (i == 0 or j > 0) else WD_ALIGN_PARAGRAPH.LEFT

doc.save(DOCX)

# ============ 生成 md ============
lines = []
for kind, val in BLOCKS:
    if kind == "h1":
        lines += ["# " + val, ""]
    elif kind == "h2":
        lines += ["## " + val, ""]
    elif kind == "h3":
        lines += ["### " + val, ""]
    elif kind == "p":
        lines += [val, ""]
    elif kind == "li":
        lines += ["- " + val, ""]
    elif kind == "ph":
        lines += ["> " + val, ""]
    elif kind == "note":
        lines += ["<!-- " + val + " -->", ""]
    elif kind == "table":
        title, rows = val
        lines += ["**" + title + "**", ""]
        lines.append("| " + " | ".join(rows[0]) + " |")
        lines.append("|" + "|".join(["---"] * len(rows[0])) + "|")
        for row in rows[1:]:
            lines.append("| " + " | ".join(row) + " |")
        lines.append("")
io.open(MD, "w", encoding="utf-8", newline="\n").write("\n".join(lines))

# ============ 字数统计（受限章节） ============
import re
def cn_len(t):
    return len(re.sub(r"\s", "", t))

sections = {}
cur = None
for kind, val in BLOCKS:
    if kind == "h2":
        cur = None                      # 遇到上一级标题即结束本节统计
    elif kind == "h3":
        cur = val
        sections[cur] = ""
    elif kind in ("p", "li") and cur:
        sections[cur] += val
limits = {"功能与特性": 400, "应用领域": 400, "主要技术特点": 400, "主要性能指标": 200,
          "主要创新点": 200, "设计流程": 200, "可扩展之处": 300, "心得体会": 1000}
print("=== 字数检查（上限 vs 实际）===")
for k, lim in limits.items():
    n = cn_len(sections.get(k, ""))
    flag = "OK" if n <= lim else "超限"
    print("  %-8s 上限%4d  实际%4d  %s" % (k, lim, n, flag))

abs_text = ""
grab = False
for kind, val in BLOCKS:
    if kind == "h2" and val == "摘要":
        grab = True
        continue
    if grab and kind in ("p", "li"):
        abs_text += val
    elif grab and kind == "h2":
        break
print("  摘要     上限 800  实际 %4d  %s" % (cn_len(abs_text), "OK" if cn_len(abs_text) <= 800 else "超限"))
print("docx ->", DOCX)
print("md   ->", MD)
