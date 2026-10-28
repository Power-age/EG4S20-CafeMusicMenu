from docx import Document
from docx.shared import Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn

OUT = r"D:\AAA_University\Anlu\Project\doc\作品简介.docx"

TITLE = "EG4S20 咖啡厅音乐菜单"
KEYWORDS = "音频频谱可视化 · 实时参数 OSD 调节 · 帧缓存零延迟切换"

PARAS = [
    "咖啡厅柜台上的菜单屏：立式屏体，1~3 米近距离观看；营业前换一张 TF 卡就换掉整份菜单，"
    "全天无人值守，断电重上电即恢复。相比软件栈方案，画面时序由硬件确定：切换在帧边界原子生效，"
    "按键到出画面以帧计。",

    "图像链路对内容透明：任意 BMP 自动等比适配；文字对文案透明：换促销只换卡上的位图掩膜；"
    "频谱对板上音源透明。四页画面常驻 SDRAM，翻页不重载、切换零等待；换场景只需换卡与参数，"
    "不必改一行 RTL。",

    "商品中文不烧进图里，而由 FPGA 用掩膜叠加，翻页时两侧滑入，换文案不动底图；同一张卡混放 "
    "480×360 封面与 1280×960 菜品页，小图放大铺满、大图缩小铺满，逐页独立几何，卡片可 2× 双线性放大；"
    "系统同时播放卡上的背景音乐，并把同一路送往 HDMI 的 PCM 实时算成 40 段频谱，随旋律起伏，"
    "静音时整排归零。",

    "室内暖光偏暗，亮度对比度可现场调、屏上回显；转场、七项参数面板、切歌与快进快退"
    "也同在一个固件里，无需第二套镜像。",
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
body = sum(len(x) for x in PARAS)
print("body", body, "total", body + len(TITLE) + len(KEYWORDS) + 4)
