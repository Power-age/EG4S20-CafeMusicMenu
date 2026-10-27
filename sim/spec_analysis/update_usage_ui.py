"""按 V4 UI 更新使用说明里的屏幕元素行（只做定点替换）。"""
import io

P = r"D:\AAA_University\Anlu\Project\doc\工程交互使用说明文档.md"
src = io.open(P, encoding="utf-8").read()
lines = src.split("\n")

NEW_STATUS = ("| 右上角信息条 | 深咖啡棕底 `#221A14` + 琥珀金上下亮边 `#C9A227`，x 312~632、y 12~26，一行暖白 16px 文字（2x 放大，共 20 字符宽） | "
              "格式 `<歌名>HH:MM:SS`：歌名 12 字符（来自 `track_names.mif`，如 `AIRPORT` / `BOSSA NOVA` / `JAZZ PIANO`），"
              "后接开机计时 `HH:MM:SS`（每秒走字，无 RTC 为上电计时）。切歌时整行重写；秒跳变时逐秒刷新 |")
NEW_SUB = ("| 图片说明字幕 | 画面下部全宽半透明带：文字区 x 64~576（512px，2x 放大共 32 字符宽），底条 x 56~584、y 394~418（与原画面 50% 混合） | "
           "面板关闭时滚动显示**当前图片的一句话说明**（每图一句，5×7 手写字体，仅英文大写/数字/`: - . , / ! ?`）；"
           "每 0.25 秒左移一个字符、循环播放；切图后从该句开头重新滚动；打开设置面板时整块清空 |")

changed = []
for i, ln in enumerate(lines):
    if ln.startswith("| 底部状态栏 |"):
        lines[i] = NEW_STATUS
        changed.append("status")
    if ln.startswith("| 音乐频谱 |"):
        lines.insert(i + 1, NEW_SUB)
        changed.append("subtitle")
        break

io.open(P, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
print("改动:", changed, "行数:", len(lines))
