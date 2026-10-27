# Anlu 小步推进方案 V2-08：底部常驻状态栏内容渲染

## 1. 背景与目标

对应 `项目方案.md` V2-08（"任务 8：状态栏内容渲染（曲目名/时间戳/序号/播放状态）"）。当前稳定点 E12（V2-07）：`osd_buffer`（256×16，2bit/像素）+ `font_rom`（ASCII 8×8 字库）+ `osd_renderer`（消隐期写字符、含上电 `S_CLEAR` 清屏）+ `osd_buffer_overlay`（4 类像素 alpha 混合、2x 放大）已打通，屏幕中部能显示一行米白自检串 `ANLU6`。

本步目标：在**屏幕底部常驻一行状态栏**，显示真实运行状态，并复用已验证的 OSD 链路（renderer 写 buffer、overlay 叠加显示），不新建任何存储。

字段（32 个字符宽，2x 后 512 屏宽，左/中/右三段）：

| 段 | 内容 | 来源 |
|---|---|---|
| 左 | 曲目主名（8 字符，如 `TRACK01`、`MUSIC`）+ 音量 `Vnn` | SD 卡曲目名（FAT 8.3 短名）+ 音量档 |
| 中 | 时间戳 `HH:MM:SS`（等宽，开机起计时） | 本步新建 video 域帧计数器 |
| 右 | `PICn/4` + `AUTO`/`MAN` | 当前显示图号（1~4）+ 自动/手动播放模式 |

刷新规则：**状态变化（切图/切歌/切模式/调音量）或每秒（时间跳变）时整行重写一次；不变化的帧不写，故常驻、不闪烁。**

---

## 2. 需你拍板的 4 个决策点（技术方案按推荐值写，确认方案时一并定）

| 编号 | 决策点 | 推荐 | 备选 / 影响 |
|---|---|---|---|
| D1 | 底部已有 **WELCOME 滚动横幅**（背景 y=432~472、文字 y=444~460），状态栏文字行（16px）与横幅文字行同位，会重叠 | **关闭横幅滚动文字，横幅背景条+边框保留**（作为状态栏临时深色底，V2-09 再改成渐变） | 备选：整条横幅都关（状态栏文字直接压照片/波形，对比不足）；或横幅文字留着（两条文字重叠，不可行）。推荐改动最小、与 V2-09 连续 |
| D2 | 中部自检串 `ANLU6`（V2-07 链路验证用，写在 buffer 上字符行 y=0~7）如何处理 | **V2-08 不再写中部 `ANLU6`，中部画面恢复干净**；buffer 上字符行留给 V2-10 菜单面板；overlay 只做底部单窗口 | 备选：保留中部 `ANLU6`，overlay 改双窗口（同时显示中部+底部，读口需二选一仲裁，改动更大）。自检串的验证使命已完成，推荐移除 |
| D3 | 长曲目名水平滚动（任务 8 原文要求 20px/s、首尾停留 2s） | **本步不做滚动**。工程只识别 FAT 8.3 短名（主名 ≤8 字符），状态栏左段 8 格放得下，无真实超长名 | 滚动逻辑等将来支持长文件名（V2-13 边缘渐变同期）再做；本步直接整段显示主名 |
| D4 | 字段范围 | 任务 8 四项（曲目名/时间/序号/模式）**外，顺带显示音量档 `Vnn`**（信号现成、成本低） | 若不想要音量，列布局删 3 格，中段时间更居中 |

> 说明：时间戳是**开机计时**（上电 00:00:00 起累加），板子无 RTC/联网，不是实时时钟。

---

## 3. 当前代码事实（已读真实代码，2026/10/16）

### 3.1 OSD 存储与渲染（V2-05/06/07 已建，本步复用）

- `osd_buffer.v`：4096×2bit，地址 `{wr_y[3:0],wr_x[7:0]}`；逻辑宽 256、高 16 = **32 字符列 × 2 字符行**（字符 8×8：上字符行 y=0~7、下字符行 y=8~15）。PDPW、`NOREG`、`FORCE_KEEP ON`、`FILL_ALL NONE`，单读口。
- `font_rom.v`：地址 `{ascii[6:0],row[2:0]}`，1024×8。已解析 `font_data.mem`：**ASCII 32~126 全部 94 个可打印字符都有字形**（数字、`:`、`/`、空格、`-`、`.`、大小写字母齐全），状态栏所需字符**无需扩字库**。
- `osd_renderer.v`：单字符请求接口 `req_valid/req_ascii[6:0]/req_x[7:0]/req_y[3:0]/req_type[1:0]/req_ready`；`req_x` 是字符列（写缓冲列 `{char_x[4:0],col}`）、`req_y` 是字符行起始缓冲行（`buf_wr_y=char_y+row`）。在**顶部垂直消隐期**（`frame_window & ~de`）写，遇活动区 de 拉高则回 `S_WAIT_VS`、下一帧续传。含 `S_CLEAR`（上电首帧清 4096 单元一次）。
  - **关键**：写一个"空格"字符（ascii=32，字形全 0）时，64 个像素都写 `2'b00`，等于擦除该字符格。**因此整行擦除不需要新接口**：每列字段外写空格即可，整行重写 32 字符自带擦除。
  - 单字符约 81 拍，整行 32 字符约 2592 拍；顶部垂直消隐约 2.8 万拍，**一帧消隐足以写完整行**。
- `osd_buffer_overlay.v`：当前**单窗口** `X0=64/Y0=224/W=512/H=32`，2x 放大映射整个 buffer（`rd_x=rel_x[8:1]`、`rd_y=rel_y[4:1]`）。4 类混合：01 面板 75%（`#1A1D23`）、10 文字不透明（`#F0EDE8`）、11 高亮 35%（`#E8A838`）、00 透明；混合已用移位加法（不占 DSP）。同步读 1 拍，rgb/de/vs/win 打 1 拍对齐。

### 3.2 底部现有布局（已读真实坐标）

- 波形 `waveform_render.v`：渲染区 y∈[380,428)，竖条底部到 y=427。
- WELCOME 横幅 `video_osd_overlay.v`：背景 `banner_bg_area` y∈[432,472)，上下边 `banner_edge_area`（y=432/433、470/471），**滚动文字** `banner_line_area` y∈[444,460)、阴影 y∈[446,462)。
- 最终像素合成优先级（`osd_rgb`）：左上面板 → 横幅文字 → 横幅文字阴影 → 横幅边 → 横幅背景 → 转场/原图。
- 叠加顺序（top）：图片→波形→`video_osd_overlay`（横幅/面板/转场）→**`osd_buffer_overlay`（OSD 文字，最上层）**→RGB2AXIS。

### 3.3 状态栏可用状态信号（已逐一确认）

| 字段 | 信号 | 位宽/域 | 说明 |
|---|---|---|---|
| 当前显示图号 | `e2_disp_buf_sync` | 2bit，**video 域** | 当前屏幕显示的 buffer 号 0~3，与画面严格一致；显示值 +1 = 1~4（`posedge video_clk` 块已两级同步，见 top 327~360） |
| 自动/手动 | `ape_sync` | 1bit，**video 域** | `osd_auto_play_en` 经两级同步到 video 域（top 516）；1=AUTO 自动轮播，0=MAN 手动 |
| 音量档 | `vol_level_a` → `vol_lvl_c2` | 4bit，audio→clk 域 | `audio_volume_gain` 输出，默认 12（`DEFAULT_VOL=4'd12`），范围 0~15；已同步到 clk 域，本步再两级同步到 video 域 |
| 曲目编号 | `current_track_index` | 4bit，**sd_card_clk 域** | `track_controller` 输出，0-based（TRACK01→0）；**当前未引出 sd_card_bmp 端口**，本步加端口引出 |
| 曲目名 | `current_track_name` | 88bit（11 字节），**sd_card_clk 域** | FAT 8.3 短名 `{主名8字节, 扩展名3字节}`，如 `TRACK01 RAW`、`MUSIC   WAV`，切歌时整体更新、长期稳定；**当前未引出**，本步加端口引出 |
| 时间戳 | 无 | — | 工程无秒表，本步在 video 域用 vs 帧计数新建 |

- 曲目名字节布局（`fat32_volume_scanner` 扫描）：`track_name={dir_name0..10}`，`[87:80]` 是主名第 1 字节……`[31:24]` 是主名第 8 字节，`[23:0]` 是扩展名（`RAW`/`WAV`）。短名不足 8 字符用空格 `0x20` 填充。**状态栏只显示主名 8 字节（取 `[87:24]`），空格自然留白，不显示扩展名。**
- 图片总数：SD 卡扫描目标 `SCAN_TARGET_COUNT=3'd4`（top 603），固定 4 张。

---

## 4. 屏幕布局与字符列分配（冻结）

状态栏用 buffer **下字符行 y=8~15**（`req_y=8`），2x 放大后 16px 高。

- **状态栏窗口（屏幕坐标）**：`X0=64`、`Y0=444`，宽 512（x=64..575）、高 16（y=444..459），落在横幅背景条（y=432~472）内部的文字行，水平居中。反算：`rd_x=(x-64)>>1`（0..255），`rd_y=4'd8+((y-444)>>1)`（8..15）。
- 与波形（y 到 427）、横幅边（432/433）不重叠；横幅背景条上下边 432/433/470/471 仍在，视觉上是"深色底条 + 状态文字"。

32 个字符列（列 0~31）固定分配：

| 列 | 0..7 | 8..10 | 11 | 12..19 | 20 | 21..26 | 27 | 28..31 |
|---|---|---|---|---|---|---|---|---|
| 内容 | 曲目主名（8 字符，左对齐） | `Vnn` 音量 | 空格 | `HH:MM:SS` | 空格 | `PICn/4` | 空格 | `AUTO`/`MAN` |

- 时间列细分：12=H十、13=H个、14=`:`、15=M十、16=M个、17=`:`、18=S十、19=S个。
- 右部：21=`P`、22=`I`、23=`C`、24=图号数字、25=`/`、26=`4`、27=空格；28..31 为 `AUTO` 或 `MAN`（MAN 时第 31 列补空格）。
- 示例（曲目 TRACK01、音量 12、1 分 23 秒、第 1 张、自动）：

  ```
  TRACK01 V12  00:01:23 PIC1/4 AUTO
  0         1         2         3
  01234567890123456789012345678901
  ```

- 所有文字本步统一用 `req_type=2'b10`（米白 TEXT）；高亮（11）留给后续面板。

---

## 5. 新增模块 `hdl_source/status_bar_render.v`

全部在 **video_clk（25MHz）域**。不写注释。

### 5.1 端口

```
input  wire        clk,          // video_clk
input  wire        rst,          // rst_all
input  wire        vs,           // 顶部消隐帧脉冲（与 renderer 同 vs，取 wave_vs）
input  wire        rd_done,      // 上电全屏清屏完成（renderer clr_done，未引出则用复位后固定延迟）
input  wire [87:0] track_name,   // 已同步到 video 域的曲目名
input  wire [3:0]  vol_level,    // 已同步到 video 域的音量 0~15
input  wire [1:0]  img_idx,      // e2_disp_buf_sync，0~3
input  wire        auto_en,      // ape_sync
output reg         req_valid,
output wire [6:0]  req_ascii,
output wire [7:0]  req_x,
output wire [3:0]  req_y,
output wire [1:0]  req_type,
input  wire        req_ready
```

`req_y` 固定 `4'd8`，`req_type` 固定 `2'b10`，`req_x = {2'd0,col[5:0]}`。

### 5.2 时间戳计数器

- 内部 `vs_d` 检测 vs 上升沿 `vs_rise`。
- `frame_cnt[5:0]`：每次 vs_rise 加 1，计到 60 归零并 `sec++`（60 帧/秒；640×480 实际 59.94Hz，用 60 近似，10 分钟误差 <1s，状态栏可接受，验收时如实标注）。
- `sec[5:0]` 到 60 归零、`min[5:0]` 到 60 归零、`hour[6:0]` 0~99 循环（BCD 前为二进制，显示时转两位）。

### 5.3 刷新触发与快照

- 把用于显示的稳定信号（track_name、vol_level、img_idx、auto_en、hour、min、sec）各自打一拍，与当前值比较，**任一不同**产生 `refresh_pulse`（sec 每秒变，自动每秒刷新一次；其他字段变化立即刷新）。
- 触发时把上述信号整体锁存到一组**快照寄存器**（snap_*），本次 32 字符重写全程用快照，避免写到一半秒进位导致同行不一致。
- 刷新状态机：`S_IDLE`（等 refresh_pulse）→ `S_SEND`（col=0..31 逐字符请求，req_valid 拉高；`req_ready` 握手一次 col+1；col=31 握手后回 S_IDLE）。中途新来的 refresh_pulse 不打断，下一轮再生效。
- col 计数保持，若某帧消隐没写完，renderer 下一帧重回 IDLE 后从当前 col 续传（实测一帧足够）。

### 5.4 字符生成（按 col 组合输出 7bit ASCII，字段外一律输出空格 32）

- col 0..7：`track_name[87:24]` 对应 8 字节（col0 取 `[87:80]`，依次到 col7 取 `[31:24]`），取 `[6:0]`。
- col 8：`"V"`（86）；col 9..10：音量两位十进制（00~15，不足两位前补 `0`）。
- col 11：空格。
- col 12..19：时间，数字位为 BCD+48，14/17 为 `":"`（58）。
- col 20：空格。
- col 21..23：`"P""I""C"`；col 24：图号（`img_idx+1`，1~4）+48；col 25：`"/"`（47）；col 26：`"4"`（52）；col 27：空格。
- col 28..31：`auto_en` 时 `"A""U""T""O"`，否则 `"M""A""N"` + 空格。

### 5.5 二进制转两位十进制（不引 DSP）

- 分/秒（0~59）、小时（0~99）：十位 `ten = v>=50?5:v>=40?4:v>=30?3:v>=20?2:v>=10?1:0`，个位 `one = v - ten*10`（`ten*10` 用 `(ten<<3)+(ten<<1)` 移位，无乘法器）；ASCII 位 = `ten+48`、`one+48`。
- 音量（0~15）：十位 `vol>=10?1:0`，个位 `vol - ten*10`。
- 图号（1~4）：一位，直接 `(img_idx+1)+48`。

---

## 6. 跨时钟域与 SD 模块改动

### 6.1 `SD/sd_card_bmp.v` 加两个输出端口

- 端口表新增：`output wire [3:0] cur_track_index`、`output wire [87:0] cur_track_name`，内部直接 `assign` 到已有的 `current_track_index`（140 行）/`current_track_name`（141 行）。不改内部任何逻辑。
- 这两个信号随 sd_card_clk 走，top 例化处加同名 wire。

### 6.2 top 新增 video 域两级同步

- 曲目名 88bit + 编号 4bit：各自打两拍 `n_meta/n_sync`（video_clk）。曲目名只在切歌瞬间变化、且切歌后长期保持，两级打拍即可；为杜绝切歌那一帧采集到半旧半新，编号再额外比一拍，状态栏以"同步后编号稳定"为准取对应快照（编号稳定后 name 必已稳定，下一次刷新即一致）。
- 音量 `vol_lvl_c2`（clk 域）→ 两级打拍到 video 域 `vol_v1/vol_v2`。
- 图号直接用 `e2_disp_buf_sync`、模式直接用 `ape_sync`（已是 video 域）。

---

## 7. 顶层接线改动 `top_tf_hdmi_audio.v`

1. sd_card_bmp 例化（604~649 行）新增 `.cur_track_index(...)`、`.cur_track_name(...)` 连线；声明对应 wire。
2. 新增第 6.2 节的两级同步寄存器。
3. 新建 `status_bar_render u_status_bar_render`（video_clk），输入同步后的 name/vol/img/auto 与 `wave_vs`，输出 req 组。
4. `u_osd_renderer` 的 req 源从现有 `osd_st_*` 自检串**改接 `u_status_bar_render`**（req_y 由模块固定 8）；删除/停用中部 `ANLU6` 自检串发送状态机（793~815 行的 `osd_st_*` 与例化处 736~740 的接线）。
5. `osd_buffer_overlay` 窗口改底部：`OSD_Y0=444`、`OSD_H=16`，读地址 `rd_y=4'd8+rel_y[4:1]`，`rd_x` 与 X0 不变。
6. `video_osd_overlay` 新增 `input wire I_banner_text_en`：门控 `banner_pixel`、`banner_shadow_pixel`（`... && I_banner_text_en`），背景/边框 `banner_bg_area/banner_edge_area` 不受影响；top 例化处 `.I_banner_text_en(1'b0)`（关闭 WELCOME 滚动文字）。
7. 不新增 BRAM（仍 36）、不写乘法（仍 DSP 13）、不新增锁存。

---

## 8. 仿真 `sim/tb_status_bar_render.v`（+ 扩展 overlay tb）

真实例化 `status_bar_render` + `osd_renderer` + `font_rom`（`+define+FONT_ROM_SIM`）+ `osd_buffer`（`+define+OSD_BUFFER_SIM`），产生标准 640×480 时序。

用例：
1. **首屏内容正确**：给定 `TRACK01`、V12、图 1、AUTO、时间 00:01:23，整行写满后，逐字符格（列 0~31、行 y=8~15）按 font_rom 期望字形核对，缓冲值与预期一致（含空格列全 0）。
2. **切图**：img 1→2（0→1）后触发一次刷新，列 24 变 `'2'`，其余字符不变；旧 `'1'` 位置被新内容覆盖、无残留。
3. **切模式**：auto 1→0，列 28~31 由 `AUTO` 变 `MAN`+空。
4. **秒走字与进位**：模拟 60 个 vs，秒位 +1；sec 59→00 时分位 +1（分钟进位正确）。
5. **切歌改名**：name 由 `TRACK01 RAW` 变 `TRACK02 RAW`，编号同步稳定后，列 0..7 刷成 `TRACK02`。
6. **不闪烁/不花屏**：无变化的帧不产生写请求；字段外缓冲单元恒为 0；连续多帧不重复刷屏。
7. **音量**：vol 由 12→0，列 9..10 由 `12` 变 `00`。
扩展 `tb_osd_buffer_overlay`（或新 tb）：底部窗口 y=444..459 映射正确、文字 16px 高、窗口外（含原中部 y=224）全部透明。
全部用例打印 `PASS tb_status_bar_render`。

---

## 9. 验收

- **本地（助手）**：ModelSim 上述用例全部 PASS；生产 RTL 全量 `vlog -f list.f`（新增 `status_bar_render.v` 后 60 文件）0 错误，无新增锁存/隐式线网，warning 与基线一致。
- **用户 TD**：Add Source `status_bar_render.v`（sd_card_bmp.v / video_osd_overlay.v / osd_buffer_overlay.v / top 为已在工程文件，改后直接重综合）；跑 `syn_1`（核对 **BRAM9K 仍 36、DSP 仍 13、LATCH 0**，LUT/REG 因状态机与 BCD 略增）、`phy_1`/bitgen 上板。
- **上板现象**：
  1. 底部横幅深色条上出现一行米白状态栏，格式 `TRACKxx Vnn HH:MM:SS PICn/4 AUTO/MAN`，常驻不闪烁。
  2. 时间每秒走字、秒/分进位正确。
  3. 切图右部 `PICn/4` 跟随；切自动/手动模式末段在 AUTO/MAN 间变；音量加减 `Vnn` 跟随；切歌左段曲目名跟随。
  4. 中部不再有 `ANLU6`（画面恢复干净）；WELCOME 滚动文字消失，横幅背景条与上下边仍在。
  5. 波形（y 到 427）、左上面板、切图、音乐、亮度对比度、转场、转场动画全部无回归。
- **时序**：HWNS 保持正裕量（0 hold 违例）；SWNS 维持约 −6.7ns（125MHz SDRAM 既有遗留，与本步无关）。

---

## 10. 回退点与风险

- **回退**：req 接回 `osd_st_*` 自检串、overlay 窗口改回 `(64,224,512,32)` 与 `rd_y=rel_y[4:1]`、`I_banner_text_en` 接 1（恢复横幅文字）、删除 `status_bar_render` 例化；sd_card_bmp 新端口悬空无害。即回 E12。
- **风险**：
  1. 88bit 曲目名跨域采集撕裂——只在切歌瞬间可能，编号稳定门控 + 下帧刷新自愈，用例 5 覆盖。
  2. 整行 32 字符未在一个消隐窗口写完——实测 2592 拍 ≪ 顶部消隐，col 保持续传兜底。
  3. BCD 转换意外综合成 DSP/除法器——一律用比较 + 移位，验收核对 DSP 仍 13。
  4. 底部深色条与米白文字对比度——横幅底色 `#101820`、文字 `#F0EDE8`，对比足够；若偏暗由 V2-09 渐变统一调整。
  5. 关闭横幅文字后视觉变化——本步预期内（D1），背景条保留不致空洞。

## 11. 任务过程记录

- 2026/10/16：本方案建立，等待用户确认 D1~D4 后实现；确认前不改任何 RTL。
- 2026/10/16：D1~D4 按推荐值确认后 RTL 全部落地（`status_bar_render.v` 新建；`sd_card_bmp.v` 加 cur_track_index/name 两端口；top 加两级同步、例化状态栏、删除 ANLU6 自检串状态机；`osd_buffer_overlay.v` 窗口移底部 (64,444,512×16)、rd_y=8+；`video_osd_overlay.v` 加 I_banner_text_en 并接 0）。本地复核：生产 RTL 60 文件 vlog 0 错（83 warning 同基线）；`tb_status_bar_render` 全用例 PASS、`tb_osd_buffer_overlay` 全帧 307200 像素 0 错。
- 2026/10/16（用户 18:28~18:30 跑 TD）：syn_1/phy_1/bitgen 完成。phy_1：LUT 15537/19600(79.27%)、**slices 8737(89.15%)**、BRAM9K 36（不增）、DSP 13（不增）、Setup WNS −6699ps/601 端点（与 E11/E12 相同的 125MHz SDRAM 既有遗留）、Hold WNS +12ps、0 hold 违例（布局阶段一度 −11ps/11 端点，布线后修复）。
- 2026/10/16（上板）：用户确认 §9 五项现象全部正常——状态栏常驻不闪烁、时间每秒走字进位正确、切图/切模式/音量/切歌各字段跟随、中部 ANLU6 与 WELCOME 滚动文字消失（背景条+边框保留）、波形/面板/切图/音乐/亮度对比度/转场/拔卡无回归。**V2-08 验收通过，建立 E13，本方案归档。** 资源警示：slices 89.15% 已近 90% 红线，V2-09 起每步核对资源并优先复用 osd_buffer 上字符行，详见台账 5.29 与 §6 第 12 条。
