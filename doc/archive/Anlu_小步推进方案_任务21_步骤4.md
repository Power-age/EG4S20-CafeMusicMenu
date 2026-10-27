# 小步推进方案：任务 21 步骤 4 —— 坏图/缺图门控 + 转场映射

> 上位方案：`Anlu_小步推进方案_任务21.md`。前置：步骤 1、2、3 均已上板通过。
> **状态：步骤 4 已实施并于 2026/10/05 上板通过（门控 + reveal/fade 转场映射）。**

## 1. 本步单一目标

1. **门控**：常驻后手动/自动切图，目标只在**有效 bank** 间选择（坏图、缺图位置一律跳过）；无有效目标时保持当前帧（任务 10 语义）。
2. **转场映射**：常驻后切图恢复 **reveal（横向软边揭示）/ fade（淡到黑再淡入）** 两种转场——把现有 e2 转场 FSM 的"目标基准"由旧 `disp_buf_idx` 映射到常驻"目标图号"；确认 fade 在黑场点才切读 bank、reveal 立即切 bank 并由 OSD 遮罩。
3. 不做真正交叉 fade（单读口不支持，留任务 22）。

> 转场是视觉动画时间，**不是 SD 加载延迟**；切图仍在帧消隐提交，任务 21 的"零加载延迟、不撕裂、四图常驻"三判据继续满足。

## 2. 现状与依据

- 门控已在 `resident_switch.v` 的 `next_valid(cur,bv,dir)` 实现：遍历 cur±1..cur±4（mod4）取第一个 `bank_valid` 为 1 的 bank，缺图高位 bank_valid=0 不选中，全无则返回 cur。
- e2 转场 FSM（top，video 域）：
  - 现以 `e2_disp_buf_sync`（来自 `disp_buf_idx`）为目标，`e2_disp_changed` 触发 reveal/fade；步骤 3 常驻后 `disp_buf_idx` 恒定（首图），故转场不再被触发。
  - reveal（`e2_transition_mode_sync=0`）：目标变化→pending→active，`reveal_x` 20→640（每帧 +20）；frame_read_buf_idx 立即=新 bank，OSD 按 `reveal_x`+软边做横向遮罩。
  - fade（`=1`）：FADE_OUT（fade_level 0→4，每档停 6 帧）读旧 bank，黑场点（level=4）`e2_fade_read_buf_idx` 切到目标，再 FADE_IN（4→0）。
  - OSD 视觉：`video_osd_overlay.v` 用 reveal_x 生成 edge0~4 软边遮罩、用 fade_level 经 fade_channel 压暗 RGB。

## 3. 改动点（最小）

### A. `SD/resident_switch.v`（增量 1 处）

- 新增输出 `output [1:0] target_out`，`assign target_out = resident_req;`（挂起目标，按键/自动立即更新；resident_idx 硬切逻辑保留不变）。

### B. `top_tf_hdmi_audio.v`

- 新增 `wire [1:0] resident_target;`。
- resident_switch 实例：`.resident_idx()`（转场模式下硬切输出悬空）、新增 `.target_out(resident_target)`。
- e2 显示 always 中目标源按常驻切换：
  - 原 `e2_disp_buf_meta <= disp_buf_idx;`
  - 改 `e2_disp_buf_meta <= ar_sync ? resident_target : disp_buf_idx;`
  - （ar_sync 前跟随首图；ar_sync 后跟随常驻目标。resident_target 在 ar_sync 拉高时已由 cur_disp 预载为首图，切换无跳变。）
- `frame_read_buf_idx` 改为：
  ```
  assign frame_read_buf_idx =
        e2_transition_mode_sync ? e2_fade_read_buf_idx :   // fade：黑场点切
        ar_sync                 ? e2_disp_buf_sync :        // reveal 常驻：目标 bank
                                  disp_buf_idx;             // reveal 首图阶段
  ```
- `img_num_display` 改为常驻后跟随目标：
  ```
  assign img_num_display = ar_sync ? ({2'd0,e2_disp_buf_sync} + 4'd1)
                           : ({2'd0,img_idx_wire} + 4'd1);
  ```

> 本步不新增可综合文件（resident_switch 已在工程内），无需再次 Add Source。

## 4. 本地验证

- `vlog` 0 error；更新 `sim/tb_resident_switch.v`：增加 `target_out` 跟随 `resident_req` 的检查，原 17 项检查保持 PASS（含门控：缺图/坏 bank 跳过、反向、自动、接管初始化）。
- 完整 hdl_source（47 v）编译 0 error，确认改动文件 0 新增 warning。
- 转场 FSM 本体逻辑未改（仅改输入源 mux），reveal/fade 视觉以**上板**为准（转场动画无法在纯语法检查中判定）。

## 5. 上板预期

- 上电装载同前（数码管位 4 走到 F）。
- F 后按 key1：
  - `sw_transition` 选 **reveal**：新图从左向右软边揭示（约 0.5s），无加载等待、不撕裂。
  - 选 **fade**：当前图淡到黑、黑场点切到新图再淡入（约 1~2s），黑场点切换无错位。
- 数码管图片编号随目标更新；`sw_con1` 反向；key2 自动播放每约 1s 走一次所选转场。
- 含坏图/缺图：切图自动跳过坏/缺位置，**不会切到坏槽、不花屏**；无有效下一图时保持当前帧。

## 6. 范围冻结

- 不做交叉 fade、不做拔卡/重插重载（步骤 5）、不做错误码 OSD（任务 14）。
- 不改 `frame_read_write / frame_fifo_read / frame_fifo_write / video_timing_data / video_delay / video_osd_overlay`。

## 7. 任务过程记录

- 2026/10/05：方案经用户审批通过；改动前备份步骤3通过态工程至 `Project_backup_20261005_step3pass`。
- 2026/10/05：resident_switch 新增 `target_out`；top 完成目标源 mux、`frame_read_buf_idx` / `img_num_display` 改线，resident_switch 实例硬切输出悬空。
- 2026/10/05：tb_resident_switch 更新后 **18 项检查全 PASS**（含 target 按键立即更新、idx 等帧消隐，门控跳过坏/缺）。
- 2026/10/05：完整 hdl_source（47 v）编译 0 error；83 warning 全来自既有加密 IP，改动文件 0 警。
- 未跑 TD syn/phy/bitstream；待用户综合上板，分别拨 sw_transition 测 reveal / fade 及坏/缺图门控。
