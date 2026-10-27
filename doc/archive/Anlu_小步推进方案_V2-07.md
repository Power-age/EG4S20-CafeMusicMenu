# Anlu 小步推进方案 V2-07：视频管线 OSD Buffer 读口 + 4 类像素 alpha 混合

## 1. 背景与目标

对应 `项目方案.md` V2-07（"任务 7：视频管线 4 类像素 alpha 混合叠加"）。V2-05 已建 `font_rom`/`osd_buffer`（各 1 块 BRAM9K，`FORCE_KEEP ON`），V2-06 已建 `osd_renderer` 并在消隐期把自检串 `ANLU6` 写进 `osd_buffer`，但 **osd_buffer 的视频读口仍悬空（`rd_en=0`），屏幕上看不到**。

本步目标：新建独立叠加模块 `osd_buffer_overlay.v`，串在视频管线最末端（`video_osd_overlay` 之后、`video_rgb_to_axis` 之前），在活动区按当前像素坐标从 `osd_buffer` 读 2bit 像素类型，按 4 类做 alpha 混合，把 `ANLU6` 第一次显示到屏幕上。

**首个可见结果**：屏幕中部出现米白色 `ANLU6`（每个字符 16×16 像素）；其余画面与 E11 完全一致。不改变现有面板/横幅/波形/视频/音频/任何用户操作。不写代码注释。

## 2. 当前代码事实（已读真实代码）

- 数据通路（top）：`vout_data_raw` →（image_area 门控）`vout_data_base` → `u_waveform_render` → `vout_data_wave`（同步输出 `wave_vs/wave_de`）→ `u_video_osd_overlay`（I_de=wave_de、I_vs=wave_vs、I_rgb=vout_data_wave）→ `vout_data` → `u_video_rgb_to_axis_640x480`（I_vs=wave_vs、I_de=wave_de、I_rgb=vout_data）。
- `video_osd_overlay.v`：内部用 `I_de/I_vs` 自计数 `x_cnt/y_cnt`，输出 `O_rgb` 是**组合选择**（`assign O_rgb = fade_rgb`，无输出寄存器），故 `vout_data` 与 `wave_de/wave_vs` 同相。它已含左上角面板（x12~190,y12~142）、底部滚动横幅（y432~472）、亮度/对比度、转场、fade。
- `osd_buffer.v` 读口：`rd_en/rd_x[7:0]/rd_y[3:0]` 组合给地址，**同步读 1 拍**：T 拍给地址，T+1 拍 `rd_valid=1`、`rd_data` 为该地址 2bit 数据；`rd_data = rd_valid ? memory_data : 2'd0`。
- osd_buffer 实际尺寸：地址 `{rd_y[3:0],rd_x[7:0]}`，即 **256×16 物理像素、2bit/像素**（4096 字、8192bit，1 块 BRAM9K）。
- `osd_renderer` 已写：自检串在 buffer 字符列 0~4、char_y=0（即 buffer x=0..39、y=0..7），像素类型 10（文字），字形镂空位写 00。

## 3. 坐标映射（V2-05 遗留决策，本步冻结）

`项目方案.md` 任务 7 早期写的显示区域 `x∈[192,447]、y∈[176,303]`（256×128）是按"256×128 buffer"设想的；V2-05 为把 OSD 存储压到 1 块 BRAM9K，实际 buffer 只做了 **256×16**（32 字符宽 × 2 行，字符 8×8）。二者矛盾，本步修正为与实际 buffer 一致的映射：

- **等比放大 2 倍**：每个 buffer 像素映射到屏幕 **2×2** 块。这样 8×8 字形显示为 16×16，和现有 OSD 字高一致、清晰可辨；32 字符满宽 = 256×2 = 512 屏宽（≤640，状态栏放得下）。
- **OSD 窗口（屏幕坐标）**：`X0=64`、`Y0=224`，宽 512（x=64..575）、高 32（y=224..255），水平居中、屏幕中部，避开左上现有面板（x12~190,y12~142）、底部波形（y380~427）与横幅（y432~472）。
- 反算地址：`bx = (x - X0) >> 1`（0..255）、`by = (y - Y0) >> 1`（0..15）。
- `ANLU6` 因此落在屏幕 x=64..143、y=224..239（5 个 16px 高米白字）。
- 窗口位置/缩放是临时的机制验证值；底部状态栏（V2-08）、居中设置面板（V2-10）会再定义各自位置，本步不做最终布局。

## 4. 4 类像素混合（冻结，每通道 8bit）

| 2bit | 含义 | 颜色 | 混合公式（bg=原视频，fg=OSD 色） |
|---|---|---|---|
| 00 | 透明 | — | `out = bg` |
| 01 | 面板 | `#1A1D23` | alpha75%：`out = (3*fg + bg) >> 2` |
| 10 | 文字 | `#F0EDE8` | 不透明：`out = fg` |
| 11 | 高亮 | `#E8A838` | alpha35%：`out = (3*fg + 5*bg) >> 3`（3/8=0.375，移位近似 35%） |

中间运算用 12bit 宽度，公式是凸组合（系数和为 1），结果恒 ≤255，不需要饱和钳位。

## 5. 新增模块 `hdl_source/osd_buffer_overlay.v`

- 端口：`clk, rst, I_de, I_vs, I_rgb[23:0]` → `O_de, O_vs, O_rgb[23:0]`；读口 `rd_en, rd_x[7:0], rd_y[3:0]` 输出，`rd_data[1:0], rd_valid` 输入。
- 自计数 `x_cnt[10:0]/y_cnt[9:0]`：vs 变化归零；**活动期每拍递增、消隐期归零、行末 y++**，使采样沿 x_cnt 恰为当前列（注意不能照搬纯组合的 `video_osd_overlay` 的"行首置 0 再递增"写法，否则同步读地址落后 1 列，见第 10 节）。
- 窗口与地址（当前拍组合）：`win = I_de && (x∈[X0,X0+512)) && (y∈[Y0,Y0+32))`；`rd_en=win`；`rd_x=(x-X0)>>1`、`rd_y=(y-Y0)>>1`。窗口外/消隐区 `rd_en=0`。
- **一拍对齐**：同步读 1 拍延迟，把 `I_rgb/I_de/I_vs/win` 各打一拍成 `rgb_q/de_q/vs_q/win_q`；BRAM 读数据 `rd_data` 与 `win_q` 同拍。输出：`O_de=de_q`、`O_vs=vs_q`、`O_rgb = win_q ? blend(rgb_q, rd_data) : rgb_q`（blend 为组合，按第 4 节逐通道）。整体比输入晚 1 拍，de/vs/rgb 一起晚、保持对齐。
- 不写注释。

## 6. top 接线（`top_tf_hdmi_audio.v`）

1. `u_video_osd_overlay` 的 `.O_rgb` 从 `vout_data` 改连新增 wire `vout_data_pre`。
2. 例化 `u_osd_buffer_overlay`：`I_vs=wave_vs、I_de=wave_de、I_rgb=vout_data_pre`，`O_rgb=vout_data`，`O_de/O_vs` 新增 wire `osd_de/osd_vs`；读口连 `u_osd_buffer` 的 `rd_en/rd_x/rd_y/rd_data/rd_valid`。
3. `u_osd_buffer` 读口从 `rd_en=1'b0、rd_x/rd_y=0、rd_data/rd_valid 悬空` 改为接新模块；写口仍由 `u_osd_renderer` 驱动，不改。
4. `u_video_rgb_to_axis_640x480` 的 `I_vs/I_de/I_rgb` 从 `wave_vs/wave_de/vout_data` 改为 `osd_vs/osd_de/vout_data`（三者同为新模块 1 拍延迟输出）。
5. 不新增存储（BRAM 保持 36）。

## 7. 仿真 `sim/tb_osd_buffer_overlay.v`

用 `OSD_BUFFER_SIM` 宏例化真实 `osd_buffer` + `osd_buffer_overlay`。先直接写 buffer 测试图案（buffer 坐标）：
- (bx=0,by=0) 写 01 面板、(bx=1,by=0) 写 10 文字、(bx=2,by=0) 写 11 高亮、(bx=3,by=0) 写 00 透明；其余不写/写 00。
- 再生成标准 640×480 视频时序（de/vs、x/y 扫描），输入像素统一喂纯灰 `bg=8'h808080`，逐拍比对输出（考虑固定 1 拍延迟）。

预期（在 2x 放大后，屏幕 X0=64 起）：
- 面板（屏幕 x=64..65）：R=(3×0x1A+0x80)>>2=51、G=53、B=58 → `33353A`；
- 文字（x=66..67）：`F0EDE8`；
- 高亮（x=68..69）：R=(3×0xE8+5×0x80)>>3=167、G=143、B=101 → `A78F65`；
- 透明（x=70..71）：`808080`；
- y 方向同样 2 行重复（2×2 块）。
用例：①4 类像素逐通道值正确（含 2×2 重复）；②窗口外全部透传 bg；③消隐期不读、无输出；④`O_rgb` 相对 `I_rgb` 固定 1 拍、`O_de` 与 `O_rgb` 同相不错位；⑤复位输出安全。打印 `PASS tb_osd_buffer_overlay`。

## 8. 验收

- 本地：ModelSim 全部用例 PASS；生产 RTL 全量 `vlog` 0 错误、无新增锁存/隐式线网。
- 用户 TD：Add Source `osd_buffer_overlay.v`，跑 `syn_1`（**BRAM9K 保持 36**、LATCH 0、DSP 13，LUT/REG 因混合逻辑略增）、`phy_1`/bitgen 上板。
- 上板：屏幕中部出现米白 `ANLU6`（16px 高），位置按第 3 节；视频/波形/左上 OSD/横幅/切图/音乐/亮度对比度/转场全部无回归。
- 时序：SWNS 维持约 −6.7ns（125MHz SDRAM 既有遗留）、HWNS 为正（0 hold 违例）。
- 面板（01）/高亮（11）两类的混合公式在本步由仿真逐通道验证；其真实视觉效果随 V2-08 状态栏、V2-10 设置面板实际出现时再上板确认（本步自检串只有文字，如实留待，不虚构上板结论）。

## 9. 回退点与风险

- 回退：`u_osd_buffer` 读口改回 `rd_en=0`，删 `u_osd_buffer_overlay` 例化，`video_rgb_to_axis` 接回 `wave_vs/wave_de/vout_data`，即回 E11。
- 风险：①BRAM 1 拍读延迟未对齐 → 画面错 1px/色偏（用例④对齐检查）；②2x 地址 off-by-one → 字位置/倍数错（用例①单像素 2×2 核对）；③混合溢出/色偏 → 12bit 凸组合 + 纯灰阶逐通道核对；④组合混合延迟影响 25MHz 时序 → 25MHz 周期 40ns 极宽松，phy_1 复核 HWNS。

## 10. 任务过程记录

- 2026/10/15：本方案建立，用户确认后实现。
- 2026/10/15 实现：新建 `hdl_source/osd_buffer_overlay.v`、`sim/tb_osd_buffer_overlay.v`，top 按第 6 节改 4 处。
- 仿真首次 FAIL：4 类像素颜色整体右移 2 个屏幕像素（1 个 buffer 列），奇数列正确、偶数列取到左侧一列数据。根因：坐标计数器最初沿用 `video_osd_overlay` 的"行首先置 0、次拍再递增"写法（那是纯组合模块的坐标计数）；本模块用同步 BRAM 读，地址必须在**采样沿**就等于当前列，而该写法在采样沿 x_cnt 比当列落后 1。修正为**活动期每拍递增、消隐期归零**（采样沿 x_cnt 依次为 0..639，发地址=当前列），与同步读 1 拍延迟、rgb/win 打 1 拍在同一拍汇合。
- 复跑 `PASS tb_osd_buffer_overlay`：全帧 640×480=307200 像素逐点核对 0 错误；覆盖 4 类像素颜色（面板 `33353A`、文字 `F0EDE8`、高亮 `A78F65`、透明 `808080`）、2×2 放大重复、窗口外透传、消隐不读、O_rgb 相对 I_rgb 固定 1 拍且 O_de 与 O_rgb 同相（LAG1/2/3）、复位安全。
- 全量生产 RTL `vlog -f list.f`（59 文件）：**Errors 0、Warnings 83**，与 V2-06 基线一致（全部为加密 IP `(vlog-2600) <protected>` 及 2 个既有 warning，无新增）。
- 待用户 TD：Add Source `osd_buffer_overlay.v` → `syn_1`（核对 BRAM9K 仍 36、LATCH 0、DSP 13，LUT/REG 因混合逻辑略增）→ `phy_1`/bitgen 上板。
- 上板预期：屏幕中部（x=64..143、y=224..239）出现米白 `ANLU6`（16px 高）；其余视频/波形/左上 OSD/横幅/切图/音乐/亮度对比度/转场无回归。面板（01）/高亮（11）两类的真实视觉留待 V2-08/V2-10，本步只仿真确认。

### 10.1 首次上板失败与修复（2026/10/15）

首次上板（syn_1：LUT14806/REG8414/BRAM36/**DSP15**；phy_1：LUT15213/REG8516、SWNS −7.022ns、HWNS +0.003ns）：窗口位置正确、左侧隐约见 `ANLU`，但整条 512 宽窗口右侧是彩色椒盐马赛克。两个根因：

1. **真实 BRAM 上电内容随机，未写单元未清零**：V2-06 只写了自检串 5 字符（buffer bx=0..39、by=0..7 共 40 列），其余约 4000 个单元从未写过；读窗口扫到 bx=40..255 读到随机 2bit，混成随机颜色。仿真里 testbench 先清过屏，SIM 模型未写单元为 x，没暴露。修复：`osd_renderer` 新增 `S_CLEAR(5)` 状态，复位后首帧顶部消隐期把 256×16=4096 个单元逐拍写 0（`clr_cnt[11:0]`，`clr_done` 锁存只执行一次；活动期 de 拉高则回 `S_WAIT_VS` 保计数跨帧续清，顶部消隐约 2.8 万拍远大于 4096，实际一帧清完）。这也是 V2-08 状态栏刷新所必需的擦除能力。
2. **混合乘法被综合成 DSP**：`mix75` 的 `fg*3`、`mix35` 的 `fg*3`/`bg*5` 映射出 2 个 DSP（13→15）。改为移位加法：`fg*3=fg+(fg<<1)`、`bg*5=bg+(bg<<2)`，只占 LUT。

复跑：`tb_osd_buffer_overlay` 仍 PASS（checked 307200/0 错误）；`tb_osd_renderer` 新增"用例0 上电清屏抽查"（16 个未写地址全 0）后全用例 PASS，32 字符仍 2592 拍；全量 `vlog -f list.f` 0 错、83 warning 同基线。

**本次无新增文件**（`osd_renderer.v` 为 V2-06 已在工程文件、`osd_buffer_overlay.v` 已在上轮 Add Source），直接重跑 syn_1/phy_1/bitgen 即可。预期：DSP 回到 13、BRAM9K 36、LATCH 0、HWNS 恢复正裕量、中部为清晰米白 `ANLU6` 无马赛克。

- 2026/10/15（最终上板）：重跑 syn_1/phy_1/bitgen 后上板，屏幕中部清晰显示 16px 米白 `ANLU6`、无马赛克无错位；E11 全部功能（面板/横幅/波形/切图/音乐/音量/切歌/转场）无回归。syn_1 LUT 14839/REG 8429/BRAM9K 36/DSP 13/LATCH 0；phy_1 slices 8594(87.69%)、BRAM 36、DSP 13、HWNS +11ps、0 hold 违例、SWNS −6.699ns（与 E11 相同的既有遗留）。**V2-07 验收通过，建立 E12，本方案归档**；面板（01）/高亮（11）半透明真实视觉留待 V2-10 出面板时确认。详见台账 5.28。
