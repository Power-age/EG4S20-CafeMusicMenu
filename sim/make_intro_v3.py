from docx import Document
from docx.shared import Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn

OUT = r"D:\AAA_University\Anlu\Project\doc\作品简介.docx"

TITLE = "EG4S20 咖啡厅音乐菜单"
KEYWORDS = "音频频谱可视化 · 实时参数 OSD 调节 · 帧缓存零延迟切换"

PARAS = [
    "面向数字广告牌与商业展陈终端：一台由单片安路 EG4S20 构成的 HDMI 多媒体播放系统，"
    "放在咖啡厅柜台上是会放背景音乐的电子菜单。相对通用处理器的软件栈方案，它的画面时序确定、"
    "切换延迟低、整机不依赖操作系统。",

    "从 TF 卡扫描、BMP 解析与缩放、SDRAM 帧缓存、中文图层叠加，到 HDMI 视频与 48kHz 音频输出，"
    "全部由 FPGA 内的硬件逻辑完成，不设任何额外处理器。四张画面常驻帧缓存四个分区，翻页不重新加载，"
    "切换零等待。",

    "赛题五项扩展全部实现：商品中文以卡内位图掩膜叠加，翻页时从两侧逐像素滑入；提供淡入淡出与揭幕扫入"
    "两种转场，切换过程画面连续；源图按显示器比例适配并等比缩放，另可对单张卡片做 2× 双线性放大；"
    "七项参数面板实时调节音量、亮度、对比度等并在屏上叠加信息；片内 DFT 分析正在播放的音频，"
    "40 段频谱与音乐同步起伏。",

    "逻辑资源占用 96%，视频域时序余量 11ns，帧缓存域零违例，综合无黑盒；固件已固化 Flash，上电即用。",
]


def set_font(run, name="微软雅黑", size=11, bold=False):
    run.font.name = name
    run.font.size = Pt(size)
    run.font.bold = bold
    rpr = run._element.get_or_add_rPr()
    rfonts = rpr.find(qn('w:rFonts'))
    if rfonts is None:
        rfonts = rpr.makeelement(qn('w:rFonts'), {})
        rpr.append(rfonts)
    rfonts.set(qn('w:eastAsia'), name)


doc = Document()
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
set_font(p.add_run(TITLE), size=18, bold=True)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
set_font(p.add_run("关键词："), size=10.5, bold=True)
set_font(p.add_run(KEYWORDS), size=10.5)

for body in PARAS:
    q = doc.add_paragraph()
    q.paragraph_format.space_after = Pt(8)
    q.paragraph_format.first_line_indent = Pt(22)
    set_font(q.add_run(body), size=11)

doc.save(OUT)
print("body", sum(len(x) for x in PARAS), "title+kw", len(TITLE) + len(KEYWORDS) + 4)
print("total", sum(len(x) for x in PARAS) + len(TITLE) + len(KEYWORDS) + 4)
