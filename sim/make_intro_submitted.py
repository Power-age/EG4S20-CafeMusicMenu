from docx import Document
from docx.shared import Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn

OUT = r"D:\AAA_University\Anlu\Project\doc\作品简介.docx"

TITLE = "EG4S20 咖啡厅音乐菜单"

# 2026-10-28 提交版，正文逐字保留（提交已截止，不再修改）
PARAS = [
    "面向数字广告牌与商业展陈终端：一台单片安路 EG4S20 构成的 HDMI 多媒体播放系统，"
    "放在咖啡厅柜台上就是一块会放背景音乐的电子菜单，封面加三页菜品轮番展示。"
    "相较通用处理器的软件栈方案，画面时序确定、切换延迟低、整机不依赖操作系统。",

    "从 TF 卡扫描、BMP 解析与缩放、帧缓存、中文叠加到 HDMI 视频与 48kHz 音频输出，"
    "全部在 FPGA 内由硬件逻辑完成，不设任何额外处理器。四页常驻帧缓存，翻页不重载、切换零等待。",

    "赛题五项扩展全部实现：商品中文以卡内位图掩膜叠加，翻页时从两侧逐像素滑入；"
    "淡入淡出与揭幕扫入两种转场，画面连续；同一张卡混放 480×360 封面与 1280×960 菜单页，"
    "小图放大铺满、大图缩小铺满，逐页独立几何、来回切换不串框，菜单卡片可 2× 双线性放大；"
    "七项参数面板实时调节并叠加信息；片内 DFT 分析正在播放的音频，40 段频谱随音乐起伏。",

    "资源占用 96%，视频域余量 11ns，帧缓存域零违例，综合无黑盒；固件已固化，上电即用。",
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

for body in PARAS:
    q = doc.add_paragraph()
    q.paragraph_format.space_after = Pt(8)
    q.paragraph_format.first_line_indent = Pt(22)
    set_font(q.add_run(body), size=11)

doc.save(OUT)
print("saved submitted version, body chars:", sum(len(x) for x in PARAS))
