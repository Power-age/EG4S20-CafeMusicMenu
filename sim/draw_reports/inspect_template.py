# -*- coding: utf-8 -*-
"""详查模板样式：段落样式、字体、字号、加粗、编号、对齐、缩进、页面设置。"""
import docx
from docx.shared import Pt
from docx.oxml.ns import qn

P = r"D:\AAA_University\Anlu\官方文件\材料上交\报告\技术报告模板.docx"
d = docx.Document(P)

print("=== 页面设置 ===")
s = d.sections[0]
print("  纸张: %.1f x %.1f cm" % (s.page_width.cm, s.page_height.cm))
print("  边距 左%.1f 右%.1f 上%.1f 下%.1f cm" % (s.left_margin.cm, s.right_margin.cm, s.top_margin.cm, s.bottom_margin.cm))

print("\n=== 样式表（部分）===")
for name in ("Normal", "Heading 1", "Heading 2", "Heading 3", "List Paragraph"):
    try:
        st = d.styles[name]
        f = st.font
        ea = None
        try:
            ea = st.element.rPr.rFonts.get(qn("w:eastAsia"))
        except Exception:
            pass
        print("  %-16s font=%s eastAsia=%s size=%s bold=%s" % (
            name, f.name, ea, (f.size.pt if f.size else None), f.bold))
    except KeyError:
        print("  %-16s (不存在)" % name)

print("\n=== 逐段格式 ===")
for i, p in enumerate(d.paragraphs):
    txt = p.text.strip()
    if not txt:
        continue
    pf = p.paragraph_format
    numpr = None
    try:
        pPr = p._p.pPr
        if pPr is not None and pPr.numPr is not None:
            nid = pPr.numPr.numId.val if pPr.numPr.numId is not None else None
            lvl = pPr.numPr.ilvl.val if pPr.numPr.ilvl is not None else None
            numpr = (nid, lvl)
    except Exception:
        pass
    r = p.runs[0] if p.runs else None
    rf = r.font if r is not None else None
    ea = None
    if r is not None:
        try:
            ea = r._element.rPr.rFonts.get(qn("w:eastAsia"))
        except Exception:
            pass
    print("[%02d] style=%-15s num=%-10s align=%s ind_first=%s size=%s bold=%s font=%s ea=%s | %s" % (
        i, p.style.name, str(numpr), pf.alignment,
        (pf.first_line_indent.pt if pf.first_line_indent else None),
        (rf.size.pt if rf and rf.size else None),
        (rf.bold if rf else None),
        (rf.name if rf else None), ea, txt[:40]))
