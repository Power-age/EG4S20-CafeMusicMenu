# -*- coding: utf-8 -*-
"""修双逗号 + 摘要去强调，然后重建。"""
import io, subprocess, sys

P = r"D:\AAA_University\Anlu\Project\sim\draw_reports\build_report_v2.py"
s = io.open(P, encoding="utf-8").read()

# 1) 修掉删除验证项留下的双逗号
s = s.replace('OSD 回显正确。",,', 'OSD 回显正确。",')

# 2) 摘要去掉刻意强调
old = '（1280×960、1280×960、1280×720、400×400，其中 400×400 小于输出分辨率）解码后按比例适配到 640×480 输出，小图自动放大补齐，'
new = '（1280×960、1280×960、1280×720、400×400）解码后按比例适配到 640×480 输出，'
print("abstract hit:", old in s)
s = s.replace(old, new, 1)

io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("patched")
subprocess.run([sys.executable, P], check=False)
