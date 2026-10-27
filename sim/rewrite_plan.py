import io, os, re
from pathlib import Path

DOC = Path(r"D:\AAA_University\Anlu\Project\doc")
src = DOC / "Anlu_当前方案.md"
dst = DOC / "项目方案.md"

text = io.open(src, encoding="utf-8").read()
lines = text.split("\n")

# 定位 §7 与 §8
i7 = next(i for i, l in enumerate(lines) if l.startswith("## 7."))
i8 = next(i for i, l in enumerate(lines) if l.startswith("## 8. 演示注意事项"))

new_sec = """## 7. 下一阶段任务

> 每次只推进一个任务。动手前按 `Anlu.md` 的 **B9** 规则在 `doc/` 建 `Anlu_小步推进方案_<主题>.md`，完成后归档到 `doc/archive/<日期>/`。

### 待续问题（最高优先）

**T0. 左上角源分辨率信息条（上一轮未跑通，需继续）**

- 现状：`src/user_source/hdl_source/src_info_render.v` 已实现（输出 `SRC <W>X<H>`，分辨率拆位用重复减法、不引入除法器），已登记进 `Runs/syn_1` 与 `Runs/phy_1` 两份 `.prj`；但 `tb_src_info` 抓不到字符（`got` 全 X）→ `req_valid` 从未拉高，说明重绘状态机没有被启动。`top` 与 `osd_buffer_overlay.v` 已回退到 E18.7 快照，保证源码与板上固件一致。
- 已确定的设计要点（重做时直接沿用）：
  - 存储：左上用缓冲区 **行 72、列 160~255**；右上信息条用 **行 72、列 0~19**——同行不同列，互不覆盖；
  - 窗口：左上屏幕 **x 8~200、y 12~26**（与右上同一水平线，形成左右呼应）；
  - **底条与右上角完全统一**：`#221A14` 深咖啡棕底 + `#C9A227` 琥珀金上下亮边 + `#F4EDE2` 暖白文字；
  - 内容格式 `SRC <W>X<H>`，12 字符（如 `SRC 1280X720`），长宽为当前图片的**源分辨率**。
- 下一步：用探针 tb 打印 `cst / calc_done / dirty / st` 定位启动链 → 修通 `tb_src_info` → 接回 `top` 仲裁与覆盖层窗口（含底条）→ 构建烧录上板。

### 任务清单

1. **音频测试音菜单项 `TONE` + 数字域 DDS 直出**（对应赛题基础要求③"基础音频输出"）
   - 设置面板第 7 行原本空闲，`sel_row` 上限由 5 扩到 6，面板尺寸与缓冲区行分配不变；
   - `TONE ON` → HDMI 输出内置 48kHz 测试音，右上角信息条改显 `TEST TONE`；`TONE OFF` → 正常播 WAV，右上角恢复 `歌名 -MM:SS`；
   - 测试音改为数字域 DDS 直接出 16bit 样本，与 WAV 走同一条路，替掉现有"FPGA 生成 I2S → `I2S_receiver` 25MHz 采样还原"的回环。
2. **沙沙声定位与消除**
   - 候选根因：①I2S 回环取样抖动（3.072MHz BCLK 用 25MHz 采样还原）；②WAV 流式读取欠载（SD 读与图像加载抢带宽）。
   - 诊断顺序：先做任务 1 的 `TONE` 开关 → 关掉测试音看沙沙是否消失 → 仍在则加"WAV FIFO 欠载计数器"用数码管一位显示 → 再把音量调到 0 听，判断噪声是否在音量级之后（HDMI 打包/ACR 侧）。
3. **频谱"波浪感"增强**（手段待议，先出方案对比）
   - 目标：相邻柱之间有连绵起伏的联动感，而非各柱独立跳动；
   - 不可破坏：无 AGC 的固定参考映射、16 档等 2 dB 音量、1024 点 DFT/40 段/`|I|+|Q|`/42 帧更新/3-tap 平滑+峰值保持；
   - 候选手段：时间轴平滑抽头与时间常数、空间轴相邻段插值或卷积、峰值衰减速率、`gmap` 斜率与 gamma、更新率、与 SW1/SW4 强调扫过融合。
4. **音乐进度条 + 已播 / 总长**
   - 字幕带下方细进度条（每秒更新），并与现有曲目倒计时呼应；
   - 复用已有的 `track_player_size`、帧计数与 MM:SS 换算，无新增算法。
5. **FIT / FULL 模式切换**（层次三）
   - FIT = 等比缩放 + 黑边（当前行为）；FULL = 铺满裁切；
   - 需缩放器加第二种采样策略 + 菜单项；面积预计 +100~200 LUT（当前约 94%，需盯逐域门禁）。
6. **TF 卡配置持久化 + 一键初始化**（工作量最大）
   - 卡上 `CONFIG.BIN` 存各设置项；上电读取，改动时写回；拨码开关一键恢复默认；
   - 需实现 FAT32 写（分配簇 + 改 FAT/目录 + 落盘）；若时间不足可用"默认值即最佳 + 固化烧录"替代。
7. **2026/11/1 功能冻结归档**：冻结固件 MD5 + 源码快照 + 文档齐套。

### 已舍弃（不再排期）

| 项 | 舍弃原因 |
|---|---|
| 像素级平滑滚动（逐像素字幕渲染） | 字幕已改为"整条滑入 + 15 字符/秒步进"，用户确认效果满意；投入产出比过低 |
| 双板主从架构 | 赛题非强制，单板已覆盖全部基础要求 + 5 项加分项 |
| QSPI Flash 存配置 | 需板卡原理图且可能与 bitstream 擦写冲突；改用 TF 卡方案 |
| 快进/快退 | 需在簇链上做 seek 并处理音频缓冲/爆音，工作量与剩余时间不匹配 |
| 设计报告 / 演示视频 / 提交物清单 | 用户 2026/10/24 明确暂不考虑，本轮从方案中剔除 |

### 每项任务的固定动作

- 建小步推进方案 → 用户确认 → 改代码 → 仿真 → 综合/布线（`seed_sweep.ps1` 按判据选种）→ 同步 `best_result/` → 命令行烧录 → 上板验收 → 追加台账 → 同步 `工程交互使用说明文档.md`（用户可感知变更）。

"""

out = lines[:i7] + new_sec.split("\n") + lines[i8:]
text2 = "\n".join(out)

# 标题与文档分工说明中的文件名同步
text2 = text2.replace("# 安路 FPGA 竞赛 · 当前方案（2026-10-24 定稿，含决策纪要）",
                      "# 安路 FPGA 竞赛 · 项目方案（2026-10-24 重拟，含决策纪要）")
text2 = text2.replace("**本文** —— **现行方案件**：定位 / 功能清单与采分对照 / 参数 / 构建烧录 / 波次计划 / 演示注意",
                      "**本文** —— **现行方案件**：定位 / 功能清单与采分对照 / 参数 / 构建烧录 / 任务清单 / 演示注意")
text2 = text2.replace("`doc/Anlu_当前方案.md`", "`doc/项目方案.md`")

io.open(dst, "w", encoding="utf-8", newline="\n").write(text2)
print("已写:", dst.name, "行数:", len(text2.split("\n")))
if dst.resolve() != src.resolve():
    src.unlink()
    print("已删除旧文件:", src.name)

# 同步 Anlu.md 中的引用
rules = DOC / "Anlu.md"
r = io.open(rules, encoding="utf-8").read()
n1 = r.count("Anlu_当前方案.md")
r = r.replace("Anlu_当前方案.md", "项目方案.md")
# 修正"项目方案.md 已归档"造成的自相矛盾
r = r.replace("该文件已于 2026/10/24 归档（内容停留在早期 V1/V2 任务批次）。**现行方案件 = `项目方案.md`**（含附录 A 决策与判据）",
              "早期版本的 `项目方案.md` 已于 2026/10/24 归档到 `archive/20261024/`（内容停留在 V1/V2 任务批次）。**根目录的 `项目方案.md` 是同日按用户要求重拟的现行方案件**（含附录 A 决策与判据）")
io.open(rules, "w", encoding="utf-8", newline="\n").write(r)
print("Anlu.md 引用替换次数:", n1)
