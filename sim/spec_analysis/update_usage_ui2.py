"""补齐状态栏行的替换（上次因 break 提前退出未执行）。"""
import io

P = r"D:\AAA_University\Anlu\Project\doc\工程交互使用说明文档.md"
lines = io.open(P, encoding="utf-8").read().split("\n")

NEW_STATUS = ("| 右上角信息条 | 深咖啡棕底 `#221A14` + 琥珀金上下亮边 `#C9A227`，x 312~632、y 12~26，"
              "一行暖白 16px 文字（2x 放大，共 20 字符宽） | 格式 `<歌名>HH:MM:SS`：歌名 12 字符（来自 `track_names.mif`，"
              "如 `AIRPORT` / `BOSSA NOVA` / `JAZZ PIANO`），后接开机计时 `HH:MM:SS`（每秒走字，无 RTC 为上电计时）。"
              "切歌时整行重写；秒跳变时逐秒刷新 |")

n = 0
for i, ln in enumerate(lines):
    if ln.startswith("| 底部状态栏 |"):
        lines[i] = NEW_STATUS
        n += 1

io.open(P, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
print("替换行数:", n, "总行数:", len(lines))
