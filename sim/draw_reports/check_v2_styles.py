# -*- coding: utf-8 -*-
"""校验 v2（模板基底）：抽查样式/字号是否与模板一致。"""
import docx
from docx.shared import Pt
from docx.oxml.ns import qn

P = r"D:\AAA_University\Anlu\Project\doc\报告\技术报告_木与豆咖啡_v2.docx"
d = docx.Document(P)

def info(p):
    st = p.style.name
    r = p.runs[0] if p.runs else None
    sz = r.font.size.pt if (r and r.font.size) else None
    b = r.font.bold if r else None
    ea = None
    if r is not None:
        try:
            ea = r._element.rPr.rFonts.get(qn("w:eastAsia"))
        except Exception:
            pass
    num = None
    try:
        pPr = p._p.pPr
        if pPr is not None and pPr.numPr is not None and pPr.numPr.numId is not None:
            num = pPr.numPr.numId.val
    except Exception:
        pass
    return "style=%-15s size=%-5s bold=%-5s num=%s ea=%s | %s" % (st, sz, b, num, ea, p.text.strip()[:46])

keys = ["木与豆咖啡", "摘要", "第一部分", "功能与特性", "应用领域", "主要技术特点", "主要性能指标",
        "主要创新点", "设计流程", "第二部分", "2.2.1", "2.2.2", "2.2.3", "2.3.1", "2.3.2",
        "第三部分", "工程成果", "特性成果", "第四部分", "第五部分", "[1]"]
for p in d.paragraphs:
    t = p.text.strip()
    for k in keys:
        if t.startswith(k):
            print(info(p))
            keys.remove(k)
            break

# 正文抽查：随机取几段非标题
cnt = 0
print("\n--- 正文抽查 ---")
for p in d.paragraphs:
    t = p.text.strip()
    if len(t) > 40 and p.style.name in ("Normal", "List Paragraph"):
        print(info(p))
        cnt += 1
        if cnt >= 5:
            break
print("\n表格:", len(d.tables))
for i, t in enumerate(d.tables):
    print("  表%d: %d 行 x %d 列  首行=%s" % (i + 1, len(t.rows), len(t.columns),
          " / ".join(c.text for c in t.rows[0].cells)))
