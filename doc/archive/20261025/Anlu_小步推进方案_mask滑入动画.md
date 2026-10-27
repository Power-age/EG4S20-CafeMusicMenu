# 小步推进方案：卡内文字 mask 滑入动画（E19.3 候选）

## 1. 背景与目标

对应 `项目方案.md` §7 任务 1 的剩余部分（E19.2 待办①），也是进度台账里"上次整屏黑已回退"的重做项。

**目标（单一）**：翻页后，左右两张卡片的商品文字 mask 分别从左侧、右侧滑入到位（左卡向右滑、右卡向左滑），约 0.5 秒；除此之外画面其它一切不变。

**本次不做**（防蔓延）：
- 不改 mask 的 ROM 内容 / 分辨率 / 颜色；
- 不做擦除（wipe）式动画，只做水平平移；
- 不做"局部放大"、不改频谱、不动音频；
- 不新增按键/拨码语义，动画自动跟随翻页触发。

## 2. 当前代码事实

- `src/user_source/hdl_source/mask_overlay.v`
  - 第 17~18 行：**已有** `input [9:0] slide_l, slide_r` 端口，但顶层固定接 0；
  - 第 21~23 行：左窗 x 60~260、右窗 x 360~560、y 340~420（200×80，与 ROM 行数一致）；
  - 第 27~28 行：`lx = x - LWX0 + slide_l`、`rx = x - RWX0 - slide_r`；
  - 第 29~31 行：`in_l`/`in_r` 用 `lx < 200` / `rx < 200` 判有效，越界时不画（保留背景）；
  - 结论：**偏移量取 200 时文字完全落在窗外（等价隐藏），取 0 时在原位**，动画只需把这两个输入从 200 逐帧递减到 0。模块本身无需改动。
- `src/user_source/hdl_source/top_tf_hdmi_audio.v`
  - 第 1357~1370 行：`mask_overlay u_mask_overlay` 实例，`.slide_l(10'd0) / .slide_r(10'd0)` 固定 0；
  - 第 411 行：`e2_frame_pulse = e2_vs_d && !vs`（每帧一个单周期脉冲，video_clk 域）；
  - 第 412 行：`e2_disp_changed`（显示 bank 切换的单周期脉冲，即翻页时刻）；
  - 第 504 行：`e2_vs_d <= vs`；第 520~533 行：揭幕转场 `e2_transition_reveal_x` 每帧 +20（约 32 帧 ≈ 0.53s），可参考同一节拍；
  - 第 680~704 行：`video_x_cnt/video_y_cnt` 生成块（本次不动）。
- 工程文件登记：`HDMI1.4b_Transmitter_v1.0.al` 的 `<Verilog>` 段止于第 464 行（最后一条 CompileOrder 63）；`syn_1`/`phy_1` 两份 `.prj` 第 469 行是 `mask_overlay.v`、第 477 行是 `selftest_seq.v`。
- 现状 `mask_overlay` 输出级为"寄存一拍 rgb_out"，`hit_q` 为 0 时原样透传；**E19.1 的整屏黑是在这一级之外做门控造成的**（`prog` 门控 in_l/in_r 的写法），本方案**不做任何"整屏/整行输出置黑"的门控**，只改窗口内的读地址偏移，结构上不可能黑屏。

## 3. 改动步骤

### 步骤 1：新增 `mask_slide.v`（纯视频域定时器，无原语、无存储）

- 文件：`src/user_source/hdl_source/mask_slide.v`
- 接口：`clk, rst, page_changed, trans_active, frame_tick` → `output [9:0] slide`
- 行为：
  - 复位：`slide=200`、`run=1`（上电第一屏也滑入一次）；
  - `page_changed`：`slide=200`（文字立即隐藏，避免新页文字先闪在原位）、`run=0`、`pend=1`；
  - `pend && !trans_active`：`pend=0`、`run=1`（**等揭幕转场结束再滑**，两个动效不打架）；
  - `run && frame_tick`：`slide -= 7`，减到 ≤7 时归 0 并 `run=0`（29 帧 ≈ 0.48s）。
- 参数化：`STEP=7`、`START=200`，便于调快慢。

### 步骤 2：本地编译 + 仿真

- `vlog` 编译 `mask_slide.v` + 新 tb（`sim/tb_mask_slide.v`）；
- tb 覆盖：①复位后逐帧递减到 0 且停住；②翻页时立刻回 200 并冻结；③`trans_active=1` 期间不动、转落后继续；④`frame_tick` 无脉冲时不动。

### 步骤 3：顶层接入（精确编辑，两处）

1. 在 `mask_overlay u_mask_overlay` 之前插入 `mask_slide u_mask_slide (...)` 实例：
   `.clk(video_clk) .rst(rst_all) .page_changed(e2_disp_changed) .trans_active(e2_transition_active) .frame_tick(e2_frame_pulse) .slide(mask_slide_off)`；
2. 把 `u_mask_overlay` 的 `.slide_l(10'd0)` / `.slide_r(10'd0)` 改成 `.slide_l(mask_slide_off)` / `.slide_r(mask_slide_off)`。

### 步骤 4：三处工程文件登记

- `HDMI1.4b_Transmitter_v1.0.al`：在 `</Verilog>` 前追加 `mask_slide.v`（CompileOrder 64）；
- `syn_1/HDMI1.4b_Transmitter_v1.0.prj`、`phy_1/HDMI1.4b_Transmitter_v1.0.prj`：紧随 `mask_overlay.v` 追加同格式条目。

### 步骤 5：构建 → 烧录 → 抓帧

`powershell -ExecutionPolicy Bypass -File sim\loop.ps1 -Seed 17`（三门禁全过才烧录）。

## 4. 验收方式

- **仿真**：`vsim -c -do "run -all; quit"` 无 `ERROR`/超时；递减步长与停止条件符合预期。
- **构建门禁**：`black_box=0`；`emb_violation=0`；`bit` 时间戳为本次；`slices` 不超过 96.5%；`video_clk ≥ 0`、`sd_card ≥ −0.6`、`ext_mem ≥ −0.8`。
- **上板抓帧**：
  - 正常帧：文字回到原位（与 E19.2 截图一致，不重影、不丢行）；
  - 翻页后立即连抓 2~3 帧：能看到文字**半边在窗内、半边被切**的过渡态，且左卡文字偏左、右卡文字偏右；
  - 左上 `PAGE n/4`、右上歌名与倒计时、频谱、卡片照片均无变化；
  - **任何全屏黑/整行黑即判失败**，立刻回退。

## 5. 回退点与风险

- 回退基线：**E19.2**，MD5 `2BF6537F0E9510C4F81214828D442B53`（`best_result` 现有 bit 即此版本）。
- 回退步骤：把 `u_mask_overlay` 的 `slide_l/slide_r` 改回 `10'd0`，删除 `u_mask_slide` 实例（或保留文件但不实例化，按 B5），重新构建烧录，MD5 应回到 `2BF65...`。
- 源码快照：改动前把 `top_tf_hdmi_audio.v` 复制到 `sim/backups/top_E19.2_20261025.v`。
- 风险：
  - 面积：新增约 14 个触发器 + 1 个 10 位比较器（<40 LUT），当前 95.5% 有空间但可能轻微上涨；
  - 时序：全部在 25MHz `video_clk` 域内的慢速计数，不涉及时序关键路径；
  - 动效观感（滑入速度/是否与揭幕转场重复）属审美项，若用户觉得不合适只调 `STEP`，不改结构。

## 6. 任务过程记录

（执行中追加）
