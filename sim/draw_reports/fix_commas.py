# -*- coding: utf-8 -*-
"""通用修复：列表里出现的 `",,` 或 `, ,` 等重复逗号。"""
import io, re, subprocess, sys

P = r"D:\AAA_University\Anlu\Project\sim\draw_reports\build_report_v2.py"
s = io.open(P, encoding="utf-8").read()

before = s.count('",,')
s = s.replace('",,', '",')
s = re.sub(r'",\s*"', '",\n      "', s) if False else s
print('替换 ",," 次数:', before)

io.open(P, "w", encoding="utf-8", newline="\n").write(s)
subprocess.run([sys.executable, P], check=False)
