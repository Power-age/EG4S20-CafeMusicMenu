# -*- coding: utf-8 -*-
"""表题注与表同页：在 add_table_after 里给题注设置 keep_with_next。"""
import io, subprocess, sys

P = r"D:\AAA_University\Anlu\Project\sim\draw_reports\build_report_v2.py"
s = io.open(P, encoding="utf-8").read()

old = '''    t = doc.add_table(rows=len(rows), cols=len(rows[0]))'''
new = '''    cap.paragraph_format.keep_with_next = True      # 题注与表同页
    t = doc.add_table(rows=len(rows), cols=len(rows[0]))'''
assert old in s
s = s.replace(old, new, 1)
io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("表题注已设 keep_with_next")
subprocess.run([sys.executable, P], check=False)
