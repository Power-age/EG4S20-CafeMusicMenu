# -*- coding: utf-8 -*-
"""替换报告生成脚本中的“主要创新点”三条，并重建 docx。"""
import io, subprocess, sys

P = r"D:\AAA_University\Anlu\Project\sim\draw_reports\build_report_v2.py"
s = io.open(P, encoding="utf-8").read()

i = s.index("inn = [")
j = s.index("]", i) + 1

NEW = (
    'inn = [\n'
    ' "（1）实时 DFT 音频可视化：对裸 PCM 实时做 1024 点 Q15 定点 DFT、对数分 40 段，'
    '配合跨频平滑与峰值保持，柱形稳定且贴底行渲染、不遮图文；",\n'
    ' "（2）纯硬件 OSD 交互闭环：面板 7 项参数的调节、回显与生效在帧内完成，'
    '中文角标随页滑入、曲目倒计时实时刷新，1bit 掩膜逐像素叠加不破坏底图；",\n'
    ' "（3）帧边界原子切换：四图常驻 SDRAM 四分区，翻页只改分区号并在帧消隐期提交，'
    '零加载、无撕裂，响应小于一帧。",\n'
    ']'
)
s = s[:i] + NEW + s[j:]
io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("已替换创新点块")

subprocess.run([sys.executable, P], check=False)

# 校验字数
import docx, re
DOC = r"D:\AAA_University\Anlu\Project\doc\报告\技术报告_木与豆咖啡_v2.docx"
d = docx.Document(DOC)
grab, buf = False, []
for para in d.paragraphs:
    t = para.text.strip()
    if t.endswith("主要创新点"):
        grab = True
        continue
    if grab:
        if t.startswith("1.6") or t.startswith("设计流程"):
            break
        if t:
            buf.append(t)
txt = "".join(buf)
print("创新点字数:", len(re.sub(r"\s", "", txt)))
io.open(r"D:\AAA_University\Anlu\Project\doc\报告\_render\inn.txt", "w", encoding="utf-8").write("\n".join(buf))
