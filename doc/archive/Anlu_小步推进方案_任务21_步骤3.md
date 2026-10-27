# 小步推进方案：任务 21 步骤 3 —— 帧消隐提交、零延迟切图

> 上位方案：`Anlu_小步推进方案_任务21.md`。前置：步骤 1、步骤 2 均已上板通过。
> **状态：步骤 3 已实施并于 2026/10/05 上板通过（帧消隐零延迟硬切，不撕裂）。**

## 1. 本步单一目标

4 图常驻 SDRAM 后，**手动 key1 / 自动播放按 `sw_dir` 切换显示图号**；切换请求先挂起，在**帧消隐（vsync 帧边界）才提交给显示读 bank**，下一帧整帧从新 bank 读出——零加载延迟、不撕裂；坏 bank 自动跳过。

本步为**硬切（cut）**：常驻后旁路现有 e2 转场，不做 fade/wipe（转场映射在步骤 4）。

## 2. 现状与依据

- `frame_fifo_read.v` 每帧由 `read_req` 启动，在 `S_ACK` 按**当时的 `read_addr_index`** 锁存基地址，之后整帧地址自增。故只要在 `S_ACK` 之前（帧消隐期）让 index 稳定为目标 bank，下一帧即整帧读新图；帧中途不改 index，故不撕裂。
- 帧边界 tick：`e2_frame_pulse = e2_vs_d && !vs`（video_clk 域，vsync 下降沿）。
- 现有 `frame_read_buf_idx = e2_transition_mode_sync ? e2_fade_read_buf_idx : disp_buf_idx`，且 disp_buf 变化会被 e2 逻辑检测并自动触发软边揭示/fade。步骤 3 要硬切，常驻后须旁路 e2。
- `all_resident` 目前是 `sd_card_bmp.v` 内部 reg，**未输出到 top**，需新增输出端口。
- 时钟：video_clk=25MHz、sd_card_clk=100MHz、ext_mem_clk=100MHz。

## 3. 改动点（最小）

### A. 新增可综合模块 `SD/resident_switch.v`（video_clk 域，纯时序，可独立仿真）

- 端口：`clk, rst, frame_pulse, key_pulse, auto_en, bank_valid[3:0], all_resident, cur_disp[1:0], dir`；参数 `AUTO_TICKS=25_000_000`；输出 `resident_idx[1:0]`。
- 内部：`resident_req`（挂起目标图号）、`timer[31:0]`；函数 `next_valid(cur,bv,dir)`：按方向从 cur+1..cur+4（mod4）循环找第一个 `bv` 为 1 的 bank，全无则返回 cur。
- 行为：
  - `!all_resident`：`resident_idx/resident_req` 跟随 `cur_disp`（接管前预载当前显示图，保证接管瞬间无跳变），timer 清 0。
  - `all_resident`：`key_pulse` → `resident_req<=next_valid(...)`；`auto_en` 时 timer 计到 AUTO_TICKS → `resident_req<=next_valid(...)`、timer 清 0，否则 timer 清 0；**`frame_pulse` → `resident_idx<=resident_req`（帧消隐才提交）**。

### B. `SD/sd_card_bmp.v`（纯增量 1 处）

- 新增输出端口 `output all_resident_out`，`assign all_resident_out = all_resident;`。

### C. `top_tf_hdmi_audio.v`

- video_clk 域新增 2 级同步器：`bank_valid`、`all_resident`、`osd_auto_play_en`、`sw_con1`。
- key1 在 video_clk 域新增 `key_press_debounce`（25MHz，输入原始 `key1`）→ `key1_video_pulse`。
- 实例 `resident_switch`：`frame_pulse=e2_frame_pulse`、`key_pulse=key1_video_pulse`、`auto_en`=同步后 osd_auto_play_en、`bank_valid`=同步后、`all_resident`=同步后、`cur_disp=e2_disp_buf_sync`、`dir`=同步后 sw_con1，输出 `resident_idx`。
- `frame_read_buf_idx` 改为：`ar_sync ? resident_idx : (e2_transition_mode_sync ? e2_fade_read_buf_idx : disp_buf_idx)`。
- `img_num_display` 改为：`ar_sync ? ({2'd0,resident_idx}+4'd1) : ({2'd0,img_idx_wire}+4'd1)`。
- sd_card_bmp 实例加 `.all_resident_out(...)`。

> 新文件 `resident_switch.v` 需在 **TD GUI 内 Add Source** 加入工程（与任务 20 新增垫片相同口径）。

## 4. 本地验证

- `vlog` 编译 0 error；新增 `sim/tb_resident_switch.v`，场景：
  1. 全好、dir=0、手动：帧中给 key_pulse 时 idx **不变**，给 frame_pulse 后才 0→1→2→3→0（验证消隐提交、帧中不切=不撕裂）。
  2. bank_valid=4'b1101（idx1 坏）：手动 0→2→3→0，跳过坏 bank。
  3. dir=1：全好手动 0→3→2→1→0。
  4. 自动（AUTO_TICKS 取小值）：auto_en 后计满并在 frame_pulse 自动推进。
  5. 接管初始化：!all_resident 且 cur_disp=2（首好图非 bank0）时 idx 跟随 2，all_resident 后从 2 开始。
- 完整 hdl_source 编译 0 error，确认改动文件 0 新增 warning。

## 5. 上板预期

- 上电装载同步骤 2：数码管位 4 走 1→3→7→F。
- F 后按 key1：画面在**下一帧立即**切到下一张（无 SD 加载等待、无转场黑幕，硬切），数码管图片编号 1→2→3→4→1 即时跟随；sw_con1 反向；坏图位置自动跳过。
- key2 开自动播放：约 1s 自动硬切一张。
- 切换在帧消隐提交，画面不撕裂、不出现半帧混合。

## 6. 范围冻结

- 不做 fade/wipe 转场映射（步骤 4）、不做拔卡/重插重载（步骤 5）。
- 不改 `frame_read_write.v / frame_fifo_read.v / frame_fifo_write.v / video_timing_data.v / video_delay.v`，不新建异步 FIFO IP。

## 7. 任务过程记录

- 2026/10/05：完成步骤 3 方案设计，用户审批通过。
- 2026/10/05：改动前备份步骤 2 通过态工程至 `test/Project_backup_20261005_step2pass`。
- 2026/10/05：新增 `SD/resident_switch.v`；`sd_card_bmp.v` 新增 `all_resident_out` 端口；top 完成同步器、key1 video 域消抖、resident_switch 实例及 `frame_read_buf_idx` / `img_num_display` 改线。
- 2026/10/05：`sim/tb_resident_switch.v` 17 项检查全部 PASS（含"帧中按键不切、frame_pulse 后才切"的不撕裂验证，以及坏 bank 跳过、反向、自动定时、接管初始化）。
- 2026/10/05：完整 hdl_source（47 个 v）编译 0 error；83 warning 全来自既有加密 HDMI/SDRAM IP，改动文件 0 warning。
- 未执行 TD syn/phy/bitstream；待用户在 TD **Add Source `resident_switch.v`** 后重新综合上板验收。
