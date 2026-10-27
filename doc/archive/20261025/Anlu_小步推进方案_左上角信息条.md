# 小步推进方案 · 左上角源分辨率信息条（T0）

- 建立时间：2026/10/24 22:10
- 对应 `项目方案.md` §7 的 **T0（待续问题，最高优先）**
- 回退点：E18.7 固件 `A2FF13D71D89DA4E184C8AE6AA193A2A`；源码快照 `sim/backups/ui_v4_20261024/`

## 1. 当前代码事实

### 已经存在的文件

| 文件 | 状态 |
|---|---|
| `src/user_source/hdl_source/src_info_render.v` | 已实现，ModelSim 可编译；**功能未跑通** |
| `sim/tb_src_info.v` | 已写，`wait_line` 超时（抓不到任何字符，`got` 全 X），后加了 12 位覆盖位图 `line_done` 也收不满 |
| `Runs/syn_1/*.prj`、`Runs/phy_1/*.prj` | 已登记 `src_info_render.v`（CompileOrder 65） |
| `top_tf_hdmi_audio.v` / `osd_buffer_overlay.v` | **已回退到 E18.7 快照**，当前未实例化该模块（源码与板上固件一致）|

### 模块设计（已定型，重做时沿用）

- 输出格式：`SRC <W>X<H>`，共 12 字符（`SRC ` + W 四位 + `X` + H 三位），前导零用空格抑制；
- 分辨率拆位：4 步重复减法小状态机（`/1000`→`/100`→`/10`→余数），不引入除法器；
- 存储位置：缓冲区**行 72、字符列 20~31**（即列 160~255）；右上角信息条占行 72、字符列 0~19；
- 屏幕窗口：**x 8~200、y 12~26**（与右上角同一水平线）；
- 底条：**与右上角完全统一** —— `#221A14` 深咖啡棕底 + `#C9A227` 琥珀金上下亮边 + `#F4EDE2` 暖白文字。

### 已知的上一轮故障

1. **综合报黑盒**：`HDL-1007 module 'src_info_render' remains a black box due to errors in its contents` —— 根因是 `dirty` 被"拆位状态机"和"重绘状态机"两个 always 块同时驱动。已改为拆位侧只发 `calc_done` 单拍脉冲、重绘侧独占 `dirty`。
2. **改完后 tb 仍抓不到字符**：`req_valid` 从未拉高，推测重绘状态机没被启动（`dirty` 初值/脉冲时序或 `st` 未离开 S_IDLE）。**尚未定位**。
3. tb 自身也修过一次：最初用"固定等 300 拍再抓"会错过首轮突发，已改为从复位后立即捕获。

## 2. 本次具体改动

### 步骤 1：定位启动链（只加探针，不改功能）

- 新建 `sim/tb_src_info_probe.v`：复位后逐拍打印 `cst / calc_done / rest / dirty / st / col / req_valid`，观察前 40 拍；
- 判据：若 `calc_done` 从未为 1 → 拆位状态机没跑（查 `changed` 与 `cst`）；若 `dirty` 恒 0 → 重绘侧没接上脉冲；若 `dirty=1` 但 `st` 仍在 S_IDLE → 状态机分支条件有问题。

### 步骤 2：按定位结果修正 RTL

- 最可能的修法：`dirty` 在重绘状态机的复位分支里显式清零，并把 `calc_done` 打一拍再采样（避免同拍竞争）。

### 步骤 3：接回顶层与覆盖层（含底条）

- `top`：实例化 `src_info_render`，`img_idx` = `e2_disp_buf_sync`，`src_w/h` = `e2_active_width_sync` / `e2_active_height_sync`；
- OSD 仲裁：优先级 `menu > subtitle > 右上信息条 > 左上信息条`，新增 `si_req_ready`；
- `osd_buffer_overlay`：新增左上窗口 `sit_win`（x 8~200、y 12~26），`rd_x = 160 + rel_x[8:1]`、`rd_y = 72 + rel_y[4:1]`，并加 `sit_q` 寄存；
- **底条**：把现有横幅（`bg_win`/`edge_row`/`bg_layer`）复用一份给左窗口，颜色常量不变，保证与右上角同款（深棕底 + 琥珀金上下亮边）。

### 步骤 4：构建 → 烧录 → 上板

- 综合确认 `black box` 计数为 0；
- 布线用 `sim/seed_sweep.ps1`，判据 `video ≥ 0`、`sd ≥ −0.6`、`ext_mem ≥ −0.8`；
- 命令行烧录（`sim/burn_jtag.tcl`）。

## 3. 验收方式

### 仿真

- `tb_src_info` 三组用例：`640X480` / `1280X720` / `800X600`，逐字符比对 `req_ascii`，并断言 `req_y == 72`、`req_x` 落在 20~31。

### 上板

1. 左上角出现 `SRC <W>X<H>`，与右上角信息条**同一水平线、同款底条**；
2. 依次切四张图，左上角应分别显示 `SRC 640X480`、`SRC 800X600`、`SRC 480X640`、`SRC 1280X720`；
3. 打开设置面板时左上角不遮挡面板（`y 12~26` 在面板 `y 168~311` 之外）；
4. 字幕、右上角信息条、菜单、频谱均不受影响。

### 时序门禁

- `video_clk` SWNS ≥ 0；`sd_card ≥ −0.6ns`；`ext_mem ≥ −0.8ns`；slices ≤ 97.5%。

## 4. 回退点与回退步骤

- 上一稳定点：**E18.7**，MD5 `A2FF13D71D89DA4E184C8AE6AA193A2A`，已烧录并验收（菜单半截已修）；
- 源码快照：`sim/backups/ui_v4_20261024/`（`top_tf_hdmi_audio.v`、`osd_buffer_overlay.v`、`subtitle_render.v`、`menu_renderer.v` 等）；
- 回退动作：把快照里的 `top_tf_hdmi_audio.v` 与 `osd_buffer_overlay.v` 覆盖回 `src/user_source/hdl_source/`，重新综合布线即可复现 E18.7；
- 若功能验证不通过，**不得留在交付路径上**（规则 B5）：保持 `top`/`overlay` 为 E18.7 版本，`src_info_render.v` 可留在树里但不实例化。

---

## 5. 执行记录

### 2026/10/24 22:20 步骤 1~2 完成：模块已跑通

**探针结论**：模块本身一直在工作（`req_valid` 正常脉冲、字符在推进），之前 tb 抓不到字符是**测试台自身问题**（监视逻辑没捕获到），不是 RTL 没启动。

**真正修掉的两个 RTL bug**（用探针直接打印字符序列时暴露）：

1. `localparam [2:0] COL_BASE = 3'd20;` —— **20 放不进 3 位，被截成 4**，导致字符写到缓冲区列 4~15（正好覆盖右上角信息条），而不是设计的 20~31。已改为 `[4:0] COL_BASE = 5'd20`。
2. 复位时 `calc_done` 置 1，导致**拆位还没算完就画了一行**（首行为残次品 `SRC  640X440`）。已改为复位后 `calc_done = 0`、`dirty = 0`，等第一次拆位完成再画。

**验证结果**（`sim/tb_src_info_probe.v`，直接打印字符）：

```
line: SRC  640X480   [y=72 x=20..31]
line: SRC 1280X720   [y=72 x=20..31]
line: SRC  480X640   [y=72 x=20..31]
SRC_INFO_PASS lines=3
```

行号 72、列 20~31、无残次首行，均符合设计。

### 待做（步骤 3~4）

- 步骤 3：接回 `top` 仲裁（`menu > subtitle > 右上 > 左上`）+ `osd_buffer_overlay` 左上窗口（x 8~200、y 12~26、`rd_x = 160 + rel_x[8:1]`、`rd_y = 72 + rel_y[4:1]`）+ **与右上角统一的下底条**（`#221A14` + `#C9A227` 上下亮边 + `#F4EDE2` 文字）；
- 步骤 4：综合（确认 black box=0）→ 布线（`seed_sweep.ps1` 判据）→ 烧录 → 上板验收四张图的源尺寸。

**当前工程状态**：`top` 与 `osd_buffer_overlay.v` 仍与 E18.7 快照一致（MD5 相同），`src_info_render.v` 未被实例化 → 源码与板上固件 `A2FF13D7…` 一致，处于安全状态。

### 2026/10/25 00:51 完成，功能验收通过

后续在步骤 3~4 上又修了三处，均已上板确认：

| # | 现象 | 根因 | 修法 |
|---|---|---|---|
| 1 | 切图后左上角不变，恒为 640×480 | `display_active_width/height` 只在**第一张图提交时**赋值一次 | 改为按 bank 记录尺寸、按当前显示 bank 选择 |
| 2 | 四张图显示 640×480 / 640×480 / 360×480 / 640×360 | `pending_active_*` 是**缩放后的显示尺寸**，不是 BMP 头里的源尺寸（640×360 正是 1280×720 按 16:9 适配的结果，360×480 是 480×640 竖版适配的结果，完全吻合） | 从 `bmp_read` 引出 BMP 头的 `source_width/height` |
| 3 | 仍显示 `0X0` | `bmp_read` 的 `width/height` 是 header 解析期中间值，载入完成时已清零 | **按用户要求改为固定显示**：`src_info_render` 内置 `TAB_W0..3 / TAB_H0..3` 常量表，按图号查表，不再做识别 |
| 4 | **上电/复位后左上角空白**，切一次图才出现 | `changed = (img_idx != idx_q)`，而 `idx_q` 复位值 0 与首图号 0 相同 → 判为"未变化" | 加 `booted` 标志：`changed = !booted \|\| (img_idx != idx_q)` |

另有两次综合级问题：`dirty` 一度被两个 always 块驱动（`HDL-8007` + `HDL-1007` 黑盒）；跨域 64 位总线无握手，加了"稳定 16 拍再解码"窗口（最终改用常量表后已无跨域）。左底条高度也改为与右上角完全一致（`OSD_Y0=8`、`OSD_H=22`，文字窗口内缩 4px）。

**最终交付**：E18.9，MD5 `2CDFBFABB8AC5B3F4D117824DF3A02FC`，slices 95.11%，`video_clk` +10.016ns / 0 违例，`sd_card` −0.686ns，`ext_mem` −0.988ns。上板验收：上电即显示、复位即显示、四张图依次 640X480 / 800X600 / 480X640 / 1280X720、左框与右框同款同高。

**换图须知**：尺寸是写死的，换图时需同步修改 `src_info_render.v` 的 `TAB_W0..3 / TAB_H0..3` 四个 localparam。
