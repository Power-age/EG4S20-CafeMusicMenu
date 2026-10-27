from docx import Document
from docx.shared import Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn

OUT = r"D:\AAA_University\Anlu\Project\doc\作品简介.docx"

TITLE = "EG4S20 咖啡厅音乐菜单"
KEYWORDS = "换卡即换内容 · 单芯片全链路 · 片内音画同步"

PARAS = [
    "这是一台放在咖啡厅柜台上的电子菜单：四页画面轮流翻动，每页两件商品，图文价各就各位；"
    "背景放着钢琴曲，频谱跟着音乐起伏。"
    "整台设备只有一块 FPGA，没有处理器和操作系统，从读卡、缩放、叠加到输出 HDMI 全靠硬件完成。",

    "上电后板子扫描 TF 卡，四张画面常驻 SDRAM 的四个区，翻页没有加载等待。图片先按演示显示器适配："
    "4:3 排版加横向预压缩，拉伸后不变形、不留黑边；再由 FPGA 等比缩到 640×480。"
    "商品中文不画在图里，而是做成位图掩膜存在卡上，由 FPGA 叠加在画面上，因此能从两侧逐像素滑入，"
    "换文案只改掩膜。长按按键把当前卡片放大两倍，放大时按相邻像素加权过渡，避免硬块锯齿。",

    "声音同样由 FPGA 直接产生：读卡上的裸 PCM，经音量控制后送入 HDMI；没有曲目时切到内置测试音，"
    "音高对齐频谱频点，柱形稳定不抖。切歌、快进十秒、亮度对比度都在面板上完成。",

    "资源占用 96%，视频时钟余量 13ns，综合无黑盒，已固化，上电即可运行。",
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
print("saved")
print("body", sum(len(x) for x in PARAS), "title+kw", len(TITLE) + len(KEYWORDS) + 4)
