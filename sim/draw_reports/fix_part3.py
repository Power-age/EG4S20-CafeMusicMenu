# -*- coding: utf-8 -*-
"""修正第三部分：总述归总述，3.1/3.2 各自有内容与占位图。"""
import io, subprocess, sys

P = r"D:\AAA_University\Anlu\Project\sim\draw_reports\build_report_v2.py"
s = io.open(P, encoding="utf-8").read()

start = s.index("# 14. 第三部分")
end = s.index('h = para_by("3.2.1")')

NEW = '''# 14. 第三部分
anchor = para_by("阐述最终实现的成果")
if anchor is not None and anchor.runs:
    anchor.runs[0].text = ("系统已完成全部基础功能与五项扩展功能，比特流固化到 QSPI Flash 后上电即可自动播放："
                           "上电后显示器自动显示菜单页并播放音乐，翻页时中文角标滑入、底部频谱持续跳动。"
                           "下面按整体效果、工程成果与特性成果三部分说明。")
    for r in anchor.runs[1:]:
        r._element.getparent().remove(r._element)

h = para_by("整体介绍（整个系统实物")
if h is not None and h.runs:
    h.runs[0].text = "整体介绍"
    for r in h.runs[1:]:
        r._element.getparent().remove(r._element)
    a = add_after(h, "系统在柜台场景下的整体形态为“开发板 + HDMI 显示器 + TF 卡”，上电后自动进入播放状态，"
                     "无需按键或联网操作；设备平放于台面，正面与斜 45° 全局照片见图 11、图 12。")
    a = add_placeholder(a, "【待补：图11  整机正面：开发板 + HDMI 显示器同框，屏幕显示菜单页与底部频谱】")
    a = add_placeholder(a, "【待补：图12  整机斜 45° 全局照，能看清桌面摆放与连线】")

h = para_by("工程成果")
if h is not None and h.runs:
    h.runs[0].text = "工程成果"
    for r in h.runs[1:]:
        r._element.getparent().remove(r._element)
    add_after(h, "工程成果分机械、电路与逻辑界面三部分：机械部分说明设备形态与摆放方式；"
                 "电路部分给出板卡、接口与固化后的上电自启状态；逻辑界面部分给出各功能的屏幕实测效果。")

'''

s = s[:start] + NEW + s[end:]
io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("第三部分已重写")
subprocess.run([sys.executable, P], check=False)
