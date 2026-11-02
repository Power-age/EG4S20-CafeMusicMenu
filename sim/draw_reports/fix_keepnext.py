# -*- coding: utf-8 -*-
"""给标题段落加 keep_with_next，给图片段落加 keep_with_next（题注跟随图）。"""
import io, subprocess, sys

P = r"D:\AAA_University\Anlu\Project\sim\draw_reports\build_report_v2.py"
s = io.open(P, encoding="utf-8").read()

anchor = 'print("缩进归一化段落数:", fixed)'
if anchor not in s:
    raise SystemExit("未找到归一化结束位置")

ADD = '''
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

'''

s = s.replace(anchor, ADD + anchor)
io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("已插入 keep_with_next 逻辑")
subprocess.run([sys.executable, P], check=False)
