import io, shutil
from pathlib import Path

DOC = Path(r"D:\AAA_University\Anlu\Project\doc")
ARCH = DOC / "archive" / "20261025"
ARCH.mkdir(parents=True, exist_ok=True)

# ---------- 1) 补完小步推进方案 §5 ----------
pd = DOC / "Anlu_小步推进方案_左上角信息条.md"
s = io.open(pd, encoding="utf-8").read()
s += """
### 2026/10/25 00:51 完成，功能验收通过

后续在步骤 3~4 上又修了三处，均已上板确认：

| # | 现象 | 根因 | 修法 |
|---|---|---|---|
| 1 | 切图后左上角不变，恒为 640×480 | `display_active_width/height` 只在**第一张图提交时**赋值一次 | 改为按 bank 记录尺寸、按当前显示 bank 选择 |
| 2 | 四张图显示 640×480 / 640×480 / 360×480 / 640×360 | `pending_active_*` 是**缩放后的显示尺寸**，不是 BMP 头里的源尺寸（640×360 正是 1280×720 按 16:9 适配的结果，360×480 是 480×640 竖版适配的结果，完全吻合） | 从 `bmp_read` 引出 BMP 头的 `source_width/height` |
| 3 | 仍显示 `0X0` | `bmp_read` 的 `width/height` 是 header 解析期中间值，载入完成时已清零 | **按用户要求改为固定显示**：`src_info_render` 内置 `TAB_W0..3 / TAB_H0..3` 常量表，按图号查表，不再做识别 |
| 4 | **上电/复位后左上角空白**，切一次图才出现 | `changed = (img_idx != idx_q)`，而 `idx_q` 复位值 0 与首图号 0 相同 → 判为"未变化" | 加 `booted` 标志：`changed = !booted \\|\\| (img_idx != idx_q)` |

另有两次综合级问题：`dirty` 一度被两个 always 块驱动（`HDL-8007` + `HDL-1007` 黑盒）；跨域 64 位总线无握手，加了"稳定 16 拍再解码"窗口（最终改用常量表后已无跨域）。左底条高度也改为与右上角完全一致（`OSD_Y0=8`、`OSD_H=22`，文字窗口内缩 4px）。

**最终交付**：E18.9，MD5 `2CDFBFABB8AC5B3F4D117824DF3A02FC`，slices 95.11%，`video_clk` +10.016ns / 0 违例，`sd_card` −0.686ns，`ext_mem` −0.988ns。上板验收：上电即显示、复位即显示、四张图依次 640X480 / 800X600 / 480X640 / 1280X720、左框与右框同款同高。

**换图须知**：尺寸是写死的，换图时需同步修改 `src_info_render.v` 的 `TAB_W0..3 / TAB_H0..3` 四个 localparam。
"""
io.open(pd, "w", encoding="utf-8", newline="\n").write(s)
shutil.move(str(pd), str(ARCH / pd.name))
print("方案已归档:", (ARCH / pd.name).name)

# ---------- 2) 台账记稳定点 ----------
led = DOC / "项目进度.md"
s = io.open(led, encoding="utf-8").read()
block = """### 稳定点 E18.9（2026/10/25 00:51，左上角源分辨率信息条 已验收，当前基线）

- **交付并已烧录验收**：MD5 **`2CDFBFABB8AC5B3F4D117824DF3A02FC`**，slices **95.11%**、`video_clk` **+10.016ns / 0 违例**、`sd_card` −0.686ns、`ext_mem` −0.988ns。
- **功能**：左上角信息条显示当前图片的源分辨率 `SRC <W>X<H>`，与右上角信息条**同一水平线、同款底条**（`#221A14` 底 + `#C9A227` 上下亮边 + `#F4EDE2` 暖白字，底条高度同为 22px）。上电/复位后立即显示；四张图依次为 640X480 / 800X600 / 480X640 / 1280X720。
- **实现**：`src_info_render.v` + 覆盖层左窗口（x 8~200、y 8~30 底条 / y 12~26 文字）+ 顶层仲裁 `menu > subtitle > 右上 > 左上`。**尺寸按用户要求改为固定常量表**（`TAB_W0..3 / TAB_H0..3`），不再从 BMP 头识别。
- **本步共修 4 个功能 bug + 2 个综合级问题**（详见归档方案 `archive/20261025/Anlu_小步推进方案_左上角信息条.md` §5）：
  1. `display_active_*` 只在首图赋值 → 按 bank 记录；
  2. `pending_active_*` 是**缩放后显示尺寸**（640×360 = 1280×720 适配结果、360×480 = 480×640 适配结果，与实测完全吻合）→ 改取源尺寸；
  3. `bmp_read` 的 `width/height` 在载入完成时已清零 → 最终改**固定表**；
  4. 上电不显示（`idx_q` 复位值与首图号相同，`changed` 恒 0）→ 加 `booted` 标志；
  5. `dirty` 多驱动致综合报黑盒（`HDL-8007`/`HDL-1007`）；
  6. 跨域 64 位总线无握手 → 加 16 拍稳定窗（改用常量表后已无跨域）。
- **归档**：`doc/archive/20261025/Anlu_小步推进方案_左上角信息条.md`（含全部执行记录）。
- **遗留**：`bmp_read` / `sd_card_bmp` 里"按 bank 记录源尺寸"的通路已不再使用，可在下一轮清掉回收面积；换图时需改 `TAB_W*/TAB_H*`。
- **下一步**：任务 1 —— 音频测试音菜单项 `TONE` + 数字域 DDS 直出。

"""
io.open(led, "w", encoding="utf-8", newline="\n").write(block + s)
print("台账已记 E18.9")

# ---------- 3) 更新方案件 §7：T0 已完成 ----------
pl = DOC / "项目方案.md"
s = io.open(pl, encoding="utf-8").read()
i0 = s.find("### 待续问题（最高优先）")
i1 = s.find("### 任务清单")
assert i0 > 0 and i1 > i0
s = s[:i0] + """### 已完成（供追溯）

**T0 左上角源分辨率信息条** —— 已于 2026/10/25 00:51 完成并上板验收（E18.9，MD5 `2CDFBFABB8AC5B3F4D117824DF3A02FC`）。执行记录见 `archive/20261025/Anlu_小步推进方案_左上角信息条.md`。尺寸为固定常量表 `TAB_W0..3 / TAB_H0..3`，换图时需同步修改。

""" + s[i1:]
io.open(pl, "w", encoding="utf-8", newline="\n").write(s)
print("方案件 §7 已更新")
