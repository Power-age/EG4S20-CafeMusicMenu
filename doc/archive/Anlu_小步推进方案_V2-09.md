# Anlu 小步推进方案 V2-09：状态栏自动淡出、淡入与波形融合

> 状态：**待用户确认决策点 D1~D5，确认前不改任何 RTL**。
> 基线：E13（2026/10/16，V2-08 底部常驻状态栏）。phy_1：LUT 15537(79.27%)、**slices 8737(89.15%)**、REG 9212、BRAM9K 36、DSP 13、HWNS +12ps、SWNS −6.699ns。

## 1. 背景与目标

V2-08 完成后，屏幕底部 y=432~472 常驻一条 40px 深色横幅（`video_osd_overlay.v` 画的纯色 `#101820` 背景 + 上下两条青色亮边），横幅内 y=444~459 是状态栏文字（`osd_buffer_overlay.v` 叠加）。V2-08 方案件 §10 风险 4 已写明"横幅偏暗/偏硬由 V2-09 统一调整"。

本步要做三件事：

1. **自动淡出/淡入**：无操作 N 秒后，整条状态栏（横幅背景 + 亮边 + 文字）在约 0.5 秒内平滑淡出，画面/波形完全露出；任意操作（切图、切模式、音量、切歌、亮度、对比度、状态码变化）立即淡入并重新计时。
2. **上沿渐变羽化（波形融合）**：横幅上沿不再是硬切线，改为 12px 纵向渐变，波形浮在画面上、下方自然过渡到深色条。
3. 观感对标竞品"地瓜丸"（设置/状态栏无操作自动隐藏）。

### 为什么拆成 V2-09a / V2-09b 两小步

slices 已 89.15%，且台账规则要求"小步单因素、判据不下调"。两因素（淡出机制、渐变几何）一起改，出问题无法定位。拆为：

| 小步 | 内容 | 资源增量（预估） | 验证点 |
|---|---|---|---|
| **V2-09a** | 横幅背景从 `video_osd_overlay` 迁到 `osd_buffer_overlay` 统一管理；新增 ui_alpha 通道；自动淡出/淡入 | 净增 **+90~180 LE** | 迁移后视觉与 E13 完全一致；淡出/淡入正确；无回归 |
| **V2-09b** | 横幅上沿 12px 羽化渐变；删除上下青色亮边 | 净增 **−20~+30 LE**（删亮边抵消渐变逻辑） | 波形与横幅自然衔接；淡出仍正常 |

**每步单独上板 + 单独核对 phy_1 资源；若 09a 后 slices ≥ 91% 或 HWNS 转负，暂停 09b，先做时序打拍（frame_fifo_write 地址乘法链、fat32_volume_scanner 长链）释放布局空间。**

---

## 2. 需拍板的 5 个决策点

| 编号 | 决策点 | 推荐 | 备选 / 影响 |
|---|---|---|---|
| D1 | 无操作保持时长与淡出时长 | **保持 5 秒（300 帧），淡出/淡入 8 档×每 4 帧变一档 ≈ 0.53 秒**（60fps 计） | 保持 3 秒更像竞品但演示时容易来不及看；8 秒更稳。时长均为参数，改常量即可 |
| D2 | AUTO 自动轮播时，每次切图（每 3 秒）算不算"操作" | **算**：切图即唤醒并重置 5 秒计时，因此 AUTO 模式下状态栏随轮播常驻；只有 MAN 模式静止才淡出 | 若只认按键，AUTO 下状态栏照样消失，评委看不到 PIC 编号变化；推荐前者 |
| D3 | 拆 09a/09b 两步 | **拆**（先淡出、上板、再渐变） | 一次全做省一轮综合，但风险叠加且资源账无法分步核 |
| D4 | 横幅底色 | 09a 沿用 `#101820`；09b 羽化后保持主色 `#101820` | 也可在 09b 顺带调成与状态栏文字面板色 `#1A1D23` 一致的色系；推荐保持，只改透明度不改色相 |
| D5 | 上下青色亮边（`#00D0FF`，y=432/433、470/471） | **09a 保留（与 E13 视觉一致），09b 随羽化一并删除** | 09a 就删则迁移前后无法逐像素对比；不推荐 |

> 另：淡出期间状态栏内部时间继续走（`status_bar_render` 照常每秒刷 buffer），淡入后直接是最新时间；无需暂停渲染。

---

## 3. 当前代码事实（已读真实代码，2026/10/17）

### 3.1 像素管线（top 732~841 行，video_clk=25MHz 域）

```
vout_data_base（图像/黑屏）
  → waveform_render        波形竖条 y∈[380,428)        → vout_data_wave
  → video_osd_overlay      左上面板/横幅/转场/亮度对比  → vout_data_pre
  → osd_buffer_overlay     状态栏文字窗口 (64,444,512×16) → vout_data（最终）
```

### 3.2 横幅现状（video_osd_overlay.v，767~811 行）

- `banner_bg_area`：I_de && y∈[432,472)，整行填 `BANNER_COLOR=24'h101820`；
- `banner_edge_area`：其中 y=432/433、470/471 填 `BANNER_EDGE_COLOR=24'h00D0FF`；
- WELCOME 滚动文字（`banner_pixel`/`banner_shadow_pixel`）V2-08 已由 `I_banner_text_en=0` 关闭，但**滚动偏移计数器 `scroll_offset`、字形函数、bg/edge 几何仍在**（常量使能下文字逻辑大概率被优化，bg/edge 确定保留）；
- 优先级链 `osd_rgb`：panel_text → border → panel → banner 文字 → 阴影 → 亮边 → 背景 → 转场。

### 3.3 状态栏叠加现状（osd_buffer_overlay.v）

- 单窗口 `X0=64,Y0=444,W=512,H=16`；`rd_en=in_win`，`rd_x=rel_x[8:1]`、`rd_y=4'd8+rel_y[4:1]`；BRAM 同步读 1 拍，rgb/de/vs/win 打 1 拍对齐；
- 4 类像素：00 透明直通、01 面板 75%（`#1A1D23`，mix75）、10 文字不透明（`#F0EDE8`）、11 高亮 35%（`#E8A838`，mix35）；全部移位加法，无 DSP；
- 当前 buffer 实际只有 00 与 10 两种内容（status_bar_render 全部发 req_type=2'b10），但 01/11 混合逻辑保留（V2-10 面板要用）；
- osd_buffer 容量 256×16×2bit，列 32~255、上字符行 y=0~7 均为 00（S_CLEAR 全清）。

### 3.4 可用的"用户操作"事件信号（全部已是 video 域，无需新跨时钟）

| 信号 | 含义 | 来源 |
|---|---|---|
| `tkn_sync` [87:0] | 当前曲目名（切歌时整体变化） | top 已有两级同步 |
| `volv_sync` [3:0] | 音量档 0~15 | top 已有两级同步 |
| `e2_disp_buf_sync` [1:0] | 当前显示图号（**手动 + 自动轮播切图都会变**） | top 已有两级同步 |
| `ape_sync` | AUTO/MAN 模式 | top 已有两级同步 |
| `brightness_level` [1:0] | 亮度档（video 域 reg） | top 124 行 |
| `contrast_level` [1:0] | 对比度档（video 域 reg） | top 125 行 |
| `state_code` [3:0] | 系统状态码（SD 扫描/加载/就绪，拔卡恢复会变） | video_osd_overlay 现输入 |

**事件定义 = 上述任一信号相对上一帧变化（边沿检测），外加复位释放。** 时间字段 HH:MM:SS 每秒变化不算事件（否则永不淡出）。

---

## 4. V2-09a 设计（自动淡出/淡入 + 横幅迁移）

### 4.1 新增模块 `hdl_source/ui_visible_ctl.v`（全 video_clk 域，不写注释）

```
input  wire        clk, rst, vs,
input  wire [87:0] track_name,
input  wire [3:0]  vol_level,
input  wire [1:0]  img_idx,
input  wire        auto_en,
input  wire [1:0]  brightness_level,
input  wire [1:0]  contrast_level,
input  wire [3:0]  state_code,
output reg  [2:0]  ui_alpha      // 0=全透明 … 7=全显示，8 档
```

- 前 6 路已是 video 域信号；`state_code` 来自 sd_card_bmp（sd_card_clk 100MHz 域，top 181/622 行），**模块内先两级同步再比较**（与数码管/OSD 现网直连的容忍度不同，变化检测不能用跨域原始值，避免亚稳态误触发唤醒）。
- 7 路输入各自打 1 拍做变化检测（88bit 整体比较），合成 `event_now = 任一路变化`。
- 4 状态 FSM，全部在 vs 上升沿逐帧动作（与 status_bar_render 的 vs 同源，取 `vs`）：

| 状态 | 进入条件 | 动作 |
|---|---|---|
| SHOW | 复位 / FADE_IN 满档 | alpha=7；`event_now`→保持计数器清零；无事件计数到 `P_HOLD_SEC*60`（默认 300）→ FADE_OUT |
| FADE_OUT | SHOW 超时 | 每 `P_FADE_STEP_FRAMES`（默认 4）帧 alpha-1；到 0 → HIDDEN |
| HIDDEN | 淡出到底 | alpha=0；`event_now` → alpha=7 直接回 SHOW（操作瞬间全亮，不必再播 0.5s 淡入，保证操作反馈跟手） |
| FADE_IN | （默认决策下不用：HIDDEN 事件直接回 SHOW） | 若希望按键后也播淡入动画，备选：每 4 帧 alpha+1 到 7 |

> D1 补充：**HIDDEN 事件"直接回 SHOW"是推荐**（操作即时全亮）；若你希望淡入也要 0.5s 动画，用 FADE_IN 行（无操作时仍然播完整 0.5s 淡入）。二选一在确认时定，默认直接回 SHOW。SHOW 中 FADE_OUT 中途事件：立即回 SHOW 并清零计时器。

- 资源：FSM 4 状态 + 帧计数（9bit，300<512）+ 步进计数（2bit）+ 7 路比较与同步（88bit 比较约 22 个 LUT，其余 4bit/2bit 若干），**估 70~100 LE**。

### 4.2 `osd_buffer_overlay.v` 改造（统一 alpha，窗口扩为整条横幅）

**窗口（09a）**：`X0=0,Y0=432,W=640,H=40`（覆盖 y=432~471，与旧横幅几何逐像素一致）。

新增端口 `input wire [2:0] I_ui_alpha`。

像素分两层（同步读时序保持，全流水打 1 拍）：

1. **系数映射（关键）**：`ui_alpha` 为 3bit（0~7），内部混合系数 `a_int = (ui_alpha==3'd7) ? 4'd8 : {1'b0,ui_alpha}`，即最高档映射为 8/8=100%。**这样 alpha=7 时横幅与文字与 E13 逐像素完全一致**（旧横幅 bg/edge 为不透明覆盖、文字不透明直出）；淡出档位为 8/8→6/8→5/8→…→0/8。
2. **背景层**（窗口内每个像素，不读 BRAM）：
   - y=432/433 或 470/471：亮边色 `#00D0FF`，系数 a_int（09a 保留亮边，D5）；
   - 其余 y：横幅色 `#101820`，系数 a_int；
   - 混合（每通道）：`out = (bg*(8-a_int) + fg*a_int) >> 3`，`8-a_int` 为 4bit 减法、常数移位加法，无 DSP。
3. **文字层**（仅在原文字窗口 x∈[64,576)、y∈[444,460) 时读 BRAM）：
   - `rd_en = text_window`；`rd_x=(x-64)>>1`（0~255）；`rd_y=4'd8+((y-444)>>1)`（8~15）；
   - 打 1 拍对齐后，rd_data：
     - 10 文字：在背景层结果上再按 a_int 叠 `TEXT_COLOR`：`out2 = (base*(8-a_int) + text*a_int) >> 3`；a_int=8 时文字不透明（与 E13 完全一致）；
     - 01 面板 / 11 高亮：保留现有 mix75/mix35 系数，再整体乘 ui_alpha（V2-10 面板用，当前无数据）；
     - 00：直通背景层结果；
   - 文字窗口外（x<64、x≥576、y<444）：rd_en 拉低，直接显示背景层（09a 无文字层）。
4. 窗口外：直通 I_rgb（与现状一致）。

- alpha=0 时：背景层公式退化为 bg（fg×0）、文字层退化为 base=bg → 整条横幅完全消失。
- **资源估算**：现状 142 LE；新增背景层 3 通道 8 档混合 + 文字层 8 档混合 + 几何/读口扩展，约 **250~300 LE（净增 110~160）**；mix75/mix35 保留。BRAM 不增、DSP 不增。

### 4.3 `video_osd_overlay.v` 删横幅

- 删 `banner_bg_area / banner_edge_area / banner_line_area / banner_shadow_line_area / banner_text_sum / banner_visible_x / scroll_offset 计数 / banner_char/glyph 相关行`；
- `osd_rgb` 优先级链删 banner 四分支（文字、阴影、亮边、背景）；
- **删端口 `I_banner_text_en`**（top 同步删 `.I_banner_text_en(1'b0)`）；
- y=432~472 区域该模块改由 `transition_rgb` 直通（转场/亮度/对比度仍作用于该区域，之后横幅再叠在最上层——与旧顺序一致：video_osd 在下层、osd overlay 在上层）；
- 左上面板、转场、亮度对比度一律不动；
- **资源估算**：净减 30~70 LE（几何比较器、滚动计数器、优先级 mux；文字 glyph 早已被常量使能优化）。

### 4.4 top 接线

1. 例化 `ui_visible_ctl u_ui_visible_ctl`（video_clk/rst_all/vs），输入 tkn_sync、volv_sync、e2_disp_buf_sync、ape_sync、brightness_level、contrast_level、state_code；
2. 新增 wire `[2:0] ui_alpha` 接到 `osd_buffer_overlay.I_ui_alpha`；
3. `video_osd_overlay` 例化删 `.I_banner_text_en(1'b0)`；
4. 其余（status_bar_render、osd_renderer、osd_buffer、font_rom）不动。

### 4.5 09a 资源预算汇总

| 项 | LE 变化（估） |
|---|---|
| 新增 ui_visible_ctl | +70~100 |
| osd_buffer_overlay 扩窗口+alpha | +110~160 |
| video_osd_overlay 删横幅 | −30~70 |
| **合计** | **+110~190 LE** |
| 预期 phy_1 | slices 89.15% → **约 89.7%~90.3%**；BRAM 36、DSP 13 不变 |

**门禁**：syn_1 先报 LUT/REG；若推算 slices >90.5%，不上 phy，先回来评估压缩 alpha 档（8→4 档可省约 30~40 LE）。

---

## 5. V2-09b 设计（上沿羽化 + 删亮边，09a 上板通过后再细化）

- 在 `osd_buffer_overlay` 背景层引入行系数 `row_a[2:0]`（y 为屏坐标）：
  - y=432~443（12 行）：row_a 由 0 线性增到 7（12 级：0,1,1,2,2,3,4,4,5,6,6,7，纯 y 比较+常量，无乘除）；
  - y=444~471：row_a=7；
- 背景最终档 `a = (row_a * ui_alpha) / 7`（3bit×3bit 小乘，综合约 9~12 LUT，>>3 近似）；
- 文字层（y≥444）row_a 恒 7，系数退化为 ui_alpha，无需额外逻辑；
- 删除 09a 保留的亮边行（约省 15~25 LE）；
- 视觉：波形 y 到 427、4px 间隙、12px 羽化（432~443）、文字黑带（444~471）。
- 净增 **−20~+30 LE**；下沿（y=471 到屏幕底 480 仅 8 行）不做羽化，深色条直接收底。

---

## 6. 仿真（本地 ModelSim，助手完成）

### 6.1 新建 `tb_ui_visible_ctl.v`
1. 复位释放 alpha=7（SHOW）；
2. 无事件连续 300 个 vs：第 300 帧起 alpha=6，此后每 4 帧减 1，32 帧后到 0 并保持（HIDDEN）；
3. HIDDEN 期间制造 img_idx 变化：下一 vs 后 alpha=7（默认直接回 SHOW）；
4. SHOW 中分别改变 track_name/vol/auto/bri/con/state_code：每次都重置保持计时器；
5. 时间字段（status_bar_render 内）变化**不**出现在本模块事件里（本模块无时间输入，天然满足）；
6. 淡出途中事件：alpha 立即回 7。

### 6.2 扩展 `tb_osd_buffer_overlay.v`
1. alpha=7：y=432~471 横幅区颜色与 E13 **逐像素一致**（含 432/433、470/471 亮边色，背景与文字均 100% 档），文字窗口字符像素与旧实现完全相同；
2. alpha=0：y=432~471 全窗口 307200 像素中该区域全部直通 I_rgb，横幅/文字零残留；
3. alpha=3（中间档）：背景、文字像素按公式逐通道核对；
4. x<64、x≥576、y=432~443 区域无文字内容泄漏；
5. 全帧 0 错，打印 `PASS tb_osd_buffer_overlay`。

### 6.3 全量编译
生产 RTL 全量 `vlog -f list.f`（新增 ui_visible_ctl.v 后 61 文件）0 错误，无新增锁存/隐式线网，warning 与基线一致（83 个加密 IP protected）。

---

## 7. 上板验收

### 7.1 V2-09a（用户 TD：Add Source ui_visible_ctl.v，改后重综合）
1. 上电后横幅 + 状态栏与 E13 视觉一致（同位置、同颜色、同亮边、同字段）；
2. MAN 模式静止：约 5 秒后整条横幅（背景+亮边+文字）在约 0.5 秒内平滑淡出，底部画面与波形完全露出；波形不闪、不中断；
3. 淡出后：切图、按 key 调音量、长按切歌、调亮度/对比度、切 AUTO/MAN，状态栏**立即全亮**（默认 D1）或 0.5 秒淡入（备选）；
4. AUTO 模式：每 3 秒轮播切图时状态栏保持可见（PICn/4 跟随），不淡出；
5. 淡出期间内部计时继续，重新显示后时间连续正确（不是从 00:00:00 重来）；
6. 无回归：四张图、波形、音乐、切图零延迟、拔卡恢复、转场、亮度对比度、左上面板、数码管全部正常；
7. 资源记录：BRAM9K=36、DSP=13；记录 LUT、slices、HWNS/SWNS 与 E13 对比。

### 7.2 V2-09b（09a 通过后）
1. 横幅上沿与波形区之间无硬切线，12px 羽化自然；亮边消失；
2. 淡出/淡入在羽化条上同样平滑；
3. 其余无回归；记录 phy_1 资源。

---

## 8. 回退点与风险

- **09a 回退**：osd_buffer_overlay 窗口改回 (64,444,512,16)、删 I_ui_alpha；video_osd_overlay 恢复横幅 bg/edge 与 I_banner_text_en 端口；删除 ui_visible_ctl 例化与文件（TD 中 Remove）。即回 E13。
- **09b 回退**：row_a 恒 7、亮边恢复。即回 09a 上板点。
- 风险：
  1. 横幅迁移后颜色/亮度与 E13 不一致——同色值、同几何，tb 6.2-1 逐像素守门；
  2. 8 档混合器综合后大于估算——syn_1 即核算，过 90.5% 不跑 phy，降到 4 档或先做时序打拍；
  3. 自动轮播时状态栏常驻被误判为 bug——D2 已明确预期行为，验收时对照；
  4. 淡出期间截图/拔卡边界——淡出只影响显示叠加，不改数据通路，拔卡恢复会使 state_code 变化自动唤醒，恰好满足预期；
  5. 文字淡入在 a=1 档可能偏淡——87.5%→12.5% 共 8 档，最低档本来就接近不可见，属正常过渡。

## 9. 任务过程记录

- 2026/10/17：方案建立，等待用户确认 D1~D5 与 09a/09b 拆分，确认前不改任何 RTL。
