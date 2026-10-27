import io

P = r"D:\AAA_University\Anlu\Project\doc\Anlu.md"
MARK = "## 2026/10/26 工程经验补充"

txt = io.open(P, encoding="utf-8").read()
idx = txt.find(MARK)
if idx < 0:
    raise SystemExit("marker not found")
head = txt[:idx].rstrip("\n")

section = """

## 2026/10/26 工程经验补充（E19.3~E19.19 一轮沉淀）

### 仿真与测试台

1. **tb 的参考模型不能复刻 DUT 的算法**。双线性放大的 `avg2` 写成 8 位相加（丢进位），tb 里也照抄了同一个错误表达式，结果"仿真全绿、上板偏色"。参考模型要用**独立写法**（如整数求和后取位）。
2. **视频类 tb 必须带垂直消隐**。原 tb 让 525 行全都有 `de`，帧内有效行数比真实多 22 行，采集/显示调度全错位，被误判成 DUT 有问题。

### 工具链与工程文件

3. **GUI 与批处理共用同一批 run 目录，GUI 侧一动就会"悄悄改工程"**：会用 `.al` 重建 `Runs/*/*.prj`（本次冲掉 13 个被例化模块），并重写 `phy_1/settings.cfg`（**删掉 `set phyWildParams {place seed N}` 整行** → 连续两次不同种子结果逐位相同，且默认种子布局极差，`ext_mem −5.8ns`）。
   → 规则：**GUI 里动过工程后，批处理前必须核对三件事**：①源文件表是否齐全 ②`place seed` 行是否存在 ③时序门禁。
4. `loop.ps1` 已加**时序门禁**：`video < 0` 或 `ext_mem < −0.8` 直接中止、不烧录（此前三门禁只看黑盒/EMB/新鲜度，把 −5.8ns 的坏 bit 烧上过板）。
5. **`seed_sweep` 的 PASS/rejected 不能只看结论**：它要求三个域同时达标，`sd_card` 一个不达标会把 `ext_mem` 很漂亮的种子否掉（本次 seed 17：`ext −0.377` 仍被判 rejected）。**必须人读表格再决策**。
6. **EMB 上限 64 是硬墙**：为取得"同时读两行"的能力把行缓冲拆成两块 512×24 BRAM → 65 块，触发 `PHY-9013`。改用**一块 1024×24 真双口 BRAM**（A 口写/读相邻行，B 口读当前行）即可。

### 视频/音频算法

7. **Verilog 里 8 位相加会丢进位**：逐通道求平均必须先扩到 9 位（`{1'b0,a}+{1'b0,b}`）再右移，否则亮部颜色直接崩。
8. **频谱"抖"分两种、根因不同**：①采样时刻抖动（I2S 回环 → 改 DDS 数字直出）；②**频谱泄漏**（音高不落在 DFT bin 上 → 把测试音频率对齐 `k×46.875Hz`，泄漏为零）。先分清是哪一种，别用平滑硬压。
9. **底噪判别法**：菜单 `VOLUME=0` 时增益查表为 0、送数字全零。此时仍有沙声 → 噪声在下游（显示器功放）；消失 → 才是我方数据问题。本次据此结案了挂了一周的"轻微沙沙"。

### 交互与视觉

10. **菜单参数快照的位宽必须按拼接总宽写**：`param_now` 实际 23 位，误写成 21 位会截掉 `sel_row` 高位，表现为"某些行切换不重绘、高亮要按两次"。
11. **动画要挂"转场结束"而不是"翻页发生"**：FADE 模式不置 `e2_transition_active`，必须用 `e2_transition_active | transition_busy_video | e2_transition_pending` 合成"转场忙"。
12. **写含反引号的文档不要用 PowerShell here-string**（`` `a ``/`` `v `` 会被当转义吃掉），改用写入工具或 Python。
"""

io.open(P, "w", encoding="utf-8", newline="").write(head + section)
print("rewritten, lines:", len((head + section).split("\n")))
