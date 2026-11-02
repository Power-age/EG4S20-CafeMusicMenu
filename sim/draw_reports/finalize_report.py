import io, os, shutil

D = r"D:\AAA_University\Anlu\Project\doc\报告"
ARC = r"D:\AAA_University\Anlu\Project\doc\archive\20261102_结题快照\报告初版_v1"
os.makedirs(ARC, exist_ok=True)

for f in ["技术报告_木与豆咖啡_v1.docx", "技术报告_木与豆咖啡_v1.pdf", "技术报告_木与豆咖啡_v1.md"]:
    p = os.path.join(D, f)
    if os.path.exists(p):
        shutil.move(p, os.path.join(ARC, f))
        print("归档:", f)

# 更新待补清单：图1/2/8/9/10 已插入
L = os.path.join(D, "待补清单.md")
s = io.open(L, "r", encoding="utf-8").read()
s = s.replace("| 图2 | 系统总体框图 | ✅ 已完成（`doc/报告/图2_系统总体框图.png`）|",
              "| 图2 | 系统总体框图 | ✅ 已绘制并插入正文 |")
s = s.replace("| 图1 | 设计流程图 | ⬜ 待画 |", "| 图1 | 设计流程图 | ✅ 已绘制并插入正文 |")
s = s.replace("| 图8 | 时钟域划分与 CDC | ⬜ 待画 |", "| 图8 | 时钟域划分与 CDC | ✅ 已绘制并插入正文 |")
s = s.replace("| 图9 | 逐像素叠加管线 | ⬜ 待画 |", "| 图9 | 逐像素叠加管线 | ✅ 已绘制并插入正文 |")
s = s.replace("| 图10 | 频谱处理流程 | ⬜ 待画 |", "| 图10 | 频谱处理流程 | ✅ 已绘制并插入正文 |")
s = s.replace("> 报告主体已按官方模板写好：`技术报告_木与豆咖啡_v1.docx`（同时提供 `.md`）。",
              "> 报告主体已按官方模板生成：`技术报告_木与豆咖啡_v2.docx`（**以官方模板为基底**，样式与自动编号完全一致；同时提供 PDF 预览）。")
io.open(L, "w", encoding="utf-8", newline="\n").write(s)
print("待补清单已更新")

# 更新推进方案：R1 完成情况
P = r"D:\AAA_University\Anlu\Project\doc\Anlu_小步推进方案_技术报告.md"
t = io.open(P, "r", encoding="utf-8").read()
add = """

---

## 8. 执行进度（2026-11-02 01:40）

### 8.1 已完成

| 项 | 结果 |
|---|---|
| R1 骨架 | **以官方模板为基底**生成：`doc/报告/技术报告_木与豆咖啡_v2.docx`（15 页 / 6 表 / 167 段）|
| 样式 | 完全沿用模板：标题 `Heading 2` 18pt；部分标题 14pt 加粗；子项 `List Paragraph` 自动编号（1.1/1.2…、3.1/3.2…）；正文 12pt 宋体 |
| 模板提示语 | 已删除 7 处（800字内/400字内/200字内等）|
| 表格 | 6 张（手工边框，9pt 宋体）|
| 图 | **图1 / 图2 / 图8 / 图9 / 图10 已绘制并插入正文**（14.4cm 宽）|
| 占位符 | 17 处红色 `【待补：图X …】`，位置与清单对应 |
| 字数 | 全部符合模板上限（摘要 698/800、创新点 167/200、心得体会 643/1000 等）|
| PDF | `技术报告_木与豆咖啡_v2.pdf`（Word 导出，15 页）|

### 8.2 剩余

| 项 | 说明 |
|---|---|
| 用户补图 | 17 张实物/截图，按 `待补清单.md` 拍摄 |
| 插图与图注 | 用户给图后我插入并统一图注 |
| R5 通读 | 术语与数字一致性、参考文献格式复核 |
| 终稿导出 | 交给用户前再导出一次 PDF |
"""
if "## 8. 执行进度" not in t:
    t += add
    io.open(P, "w", encoding="utf-8", newline="\n").write(t)
    print("推进方案已更新执行进度")
