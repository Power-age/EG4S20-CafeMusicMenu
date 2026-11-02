# -*- coding: utf-8 -*-
"""修心得体会里与“小图放大已完成”矛盾的一句。"""
import io, subprocess, sys

P = r"D:\AAA_University\Anlu\Project\sim\draw_reports\build_report_v2.py"
s = io.open(P, encoding="utf-8").read()

old = "最后按素材规格移除用不到的小图放大通路，占用从 91.8% 降到 88.1%，九个时钟域才真正全部转正。"
new = "最后把占用最高的非关键通路精简掉，占用从 91.8% 降到 88.1%，九个时钟域才真正全部转正。"
print("hit:", old in s)
s = s.replace(old, new, 1)
io.open(P, "w", encoding="utf-8", newline="\n").write(s)
subprocess.run([sys.executable, P], check=False)
