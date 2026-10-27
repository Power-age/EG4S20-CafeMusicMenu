"""更新使用说明里的字幕行与状态栏行（V5 行为）。"""
import io

P = r"D:\AAA_University\Anlu\Project\doc\工程交互使用说明文档.md"
lines = io.open(P, encoding="utf-8").read().split("\n")

SUB = ("| 图片说明字幕 | 画面下部全宽半透明带：文字区 x 64~576（512px，2x 放大共 32 字符宽），"
       "底条 x 56~584、y 394~418（与原画面 50% 混合） | 面板关闭时显示**当前图片的一句话说明**"
       "（每图一句，**每条不超过 32 字符**，可整行完整显示；5×7 手写字体，仅英文大写/数字/`- . , / ! ?`）。"
       "切图后文案从窗口左外侧**逐字符滑入**（每 4 帧挪 1 个字符，约 15 字符/秒，整条滑入约 2 秒），"
       "滑到位后**停住不动**；打开设置面板时整块清空 |")

STATUS = ("| 右上角信息条 | 深咖啡棕底 `#221A14` + 琥珀金上下亮边 `#C9A227`，x 312~632、y 12~26，"
          "一行暖白 16px 文字（2x 放大，共 20 字符宽） | 格式 `<歌名> -MM:SS`：歌名 12 字符"
          "（来自 `track_names.mif`，如 `AIRPORT` / `BOSSA NOVA` / `JAZZ PIANO`），后接"
          "**当前曲目剩余时间倒计时**（分:秒，无小时）。没有音乐播放时时间字段显示 `--:--`；"
          "切歌即刷新为新曲目时长。倒计时按 vsync 帧计数累计，与音频同步递减 |")

n = 0
for i, ln in enumerate(lines):
    if ln.startswith("| 图片说明字幕 |"):
        lines[i] = SUB
        n += 1
    elif ln.startswith("| 右上角信息条 |"):
        lines[i] = STATUS
        n += 1

io.open(P, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
print("替换行数:", n)
