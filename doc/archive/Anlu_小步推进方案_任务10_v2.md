# 小步推进方案 任务10（v2）：坏图重试 + 保持上一帧 —— 上板验收

> 对应 `项目方案.md` 任务10；上一版方案见 `archive/Anlu_小步推进方案_任务10.md`。
> 本文件为执行件，执行期间位于 `Project/doc/`，完成后移入 `Project/doc/archive/`。

## 1. 背景与目标

- 任务10 的 RTL 已实现（`bmp_read` 输出 `load_error_pulse` + `sd_card_bmp` 重试 / 坏图掩码 / 保持上一帧），但在 2026/9/27 任务12 热插拔复测时发现"**拔卡重插后第一次切换请求不生效，需额外按一次键**"，任务10 被打回"待验收"。
- 本次单一目标：在当前 E10 版本上完成任务10 的上板验收，确认两件事：
  1. **坏图路径**：坏图重试一次、再失败跳过、保持上一帧（v1 已独立验证，本次做回归）；
  2. **热插拔后首次切换**（本次重点）：拔卡重插、位4 重新回到 F 后，**第一次按 key1 即生效**，无需补按。
- 本次**不做**什么：
  - 不预先改 RTL，本次以复现 / 验收为主；
  - 不处理任务13（截断检测，已暂停）、任务14（错误码 OSD，后续任务）、scanner 阶段读错误不上报（遗留风险2）；
  - 若复现"首次切换不生效"，不直接改代码，先记录现象、定位、另给改法经用户确认。

## 2. 当前代码事实

### 2.1 坏图重试 / 保持上一帧（已实现）

- `bmp_read` 加载失败时输出 `bmp_load_error`（`load_error_pulse`，`bmp_read.v`）。
- `sd_card_bmp.v` 主状态机（第 589~606 行）：
  - 第一次 `bmp_load_error` 且 `load_retry_used=0`：置 `load_retry_used=1`，重新 `load_start_pulse` 重试同一图；
  - 第二次失败（`load_retry_used=1`）：置 `bad_image_mask[load_idx]=1`、`load_retry_used` 清零、`load_busy=0`；
  - 失败路径不更新 `display_valid / disp_buf_idx / img_idx` → 保持上一帧。
- 顺序装载（第 708~726 行）：按 `next_load_idx` 逐张写固定 bank，坏图的 `bank_valid` 不置位；全部尝试完置 `all_resident=1`。

### 2.2 常驻切图路径（video_clk 域）

- key1（切图模式）→ `key1_to_video`（top 第 304 行，`vol_mode_v=0` 时等于 key1）→ `key_press_debounce_resident`（20ms 消抖，第 533~541 行）→ `key1_video_pulse`。
- `resident_switch`（`resident_switch.v`；top 第 560~574 行例化）：
  - `ar_sync=0`（未常驻）：`resident_req / resident_idx` 跟随 `cur_disp`（= `e2_disp_buf_sync`），`key_pulse` 不生效（第 62~67 行）；
  - `ar_sync=1`：`key_pulse` 把 `resident_req <= next_valid(...)`（第 70~71 行）；`frame_pulse` 时 `resident_idx <= resident_req`（第 87~88 行）；
  - 实际显示用 `target_out = resident_req`（`resident_idx` 例化处悬空，top 第 572 行）。
- `resident_target` → `e2_disp_buf_meta`（`ar_sync=1` 时，top 第 397 行）→ `e2_disp_buf_sync` → `frame_read_buf_idx`（`ar_sync=1`、非 fade 时，第 306~309 行）→ `frame_read_write` 读 bank。

### 2.3 热插拔重插时的状态重建

- 拔卡：`sd_init_done` 变 0（任务12 超时 abort 打回 S_IDLE 并清 `sd_init_done`），`sd_card_bmp.v` 第 575~587 行清 `bank_valid / all_resident / scan_kicked / img_found_count`，但保留显示上下文（`display_valid / img_idx / disp_buf_idx` 不清，任务12 修复）。
- 重插：`sd_init_done` 重新拉高，`scan_kicked=0` 触发重新扫描（第 657~685 行），随后顺序装载、`all_resident` 重新置 1。
- 同步链：sd_card_clk 域的 `bank_valid / all_resident` 经两级 FF 同步到 video 域（`bv_sync / ar_sync`，top 第 544~557 行）。

### 2.4 可疑点（若复现失败，按此方向定位，不预设结论）

- **ar_sync 0→1 跨域窗口**：重插装载完成后 `ar_sync` 拉高有两级 FF 延迟；若首次按键落在 `ar_sync` 仍为 0 的窗口，`resident_switch` 走"跟随 cur_disp"分支，`key_pulse` 被忽略。
- **首次 key_pulse 与 frame_pulse 同周期**：新 `req` 会延迟一帧提交（正常，最多 ~16.8ms，不应完全不生效）。
- **bv_sync 未同时为 0xF**：`ar_sync` 拉高瞬间若 `bv_sync` 未稳定，`next_valid` 可能返回自身。
- 需确认：重插后首次按键时 `key1_video_pulse` 是否真正产生、`ar_sync / bv_sync` 当拍值。

## 3. 改动步骤（本次以验收为主，默认不改 RTL）

1. 步骤 A：使用当前 bitstream（`best_result`，2026/10/6 16:57 E10，已含任务10 RTL 与任务12 热插拔修复），无需重新 P&R。
2. 步骤 B：坏图路径回归（见 4.2）。
3. 步骤 C：热插拔首次切换复现（见 4.3），本次重点，重复多轮。
4. 步骤 D（条件性）：若复现"首次切换不生效"，记录并进入定位（见 4.4），不直接改 RTL。
5. 步骤 E：按结果更新台账（第 4 节状态、第 5 节记录）。

## 4. 验收方式

### 4.1 前置状态

- 拨码：SW3（C6）未拨 = 切图模式；先用 SW4 软边揭示模式（`sw_transition=1`）排除 fade 干扰，再补测 fade 模式。
- SD 卡：干净 FAT32，`PIC1~PIC4.BMP` 按顺序一次性拷入（任务13 经验：避免碎片）。
- 数码管：位4 上电应 1→3→7→F；位3 显图片编号；位5 显状态码。

### 4.2 坏图路径回归（判据）

- 造一张坏图（改 DIB 头大小 / 位深）放在某位置，上板：
  - 坏图不显示、不花屏、不卡死；
  - 内部重试一次，再失败跳过、继续后续图；
  - 显示保持上一帧正常图。
- v1 已独立验证，本次为回归，通过即可。

### 4.3 热插拔首次切换（核心判据）

- 操作循环（至少 5~10 轮，原现象为偶发）：
  1. 正常显示、切图正常（位4 = F、位3 = 编号 N）；
  2. 运行中拔出 SD 卡：最后一帧保持、位5 状态码不回 0（任务12 判据）；
  3. 重新插入 SD 卡：等待重新扫描 + 装载，位4 重新走 1→3→7→F；
  4. **位4 稳定显示 F 后，立即按一次 key1**：
     - 【通过】第一次按键即切换下一张（位3 N→N+1、画面随之变），无需补按；
     - 【失败】第一次按键无反应（位3 / 画面不变），需再按一次才切换 → 复现原问题。
- 补充：SW4 切到 fade 模式（`sw_transition=0`）再重复若干轮，确认两种转场模式都正常。
- 边界：拔卡到重插间隔可变化（快速重插 / 等待数秒再插），均应满足。

### 4.4 若复现失败（定位，不直接改 RTL）

- 记录：第几轮、拔 / 插间隔、SW4 模式、首次按键时位3 / 位4 / 位5 显示。
- 定位手段（经用户同意后）：
  - 先看现有 `hang_dbg`（位6）是否锁存；
  - 必要时临时把 `ar_sync / bv_sync / key1_video_pulse / resident_req` 引到空闲数码管位或逻辑分析仪，抓重插后首次按键当拍的 `ar_sync / bv_sync / key_pulse`；
  - 重点验证 2.4 的三个可疑点。
- 定位后单独给出 RTL 改法与影响分析，经用户确认后再改。

## 5. 回退点与风险

- 回退基线：当前稳定点 E10（台账 3.1）。本次验收不改 RTL，无回退需求；若后续定位需改 RTL，改动前以 E10 为基线，异常时按 3.1 回退链逐级回退。
- 风险 / 影响面：热插拔路径涉及 `sd_init_done / scan_kicked / all_resident / resident_switch / 两级同步器`，改动可能影响正常切图、自动播放、拔卡保持。
- 判据不下调：不因"偶发难复现"直接判通过，需按 4.3 做足轮次；若多轮（≥10）均无复现，可判通过，并在台账注明"原问题在 E10 多轮回归未复现"。

## 6. 任务过程记录

（执行中追加；历史条目不改写，发现方案有误在本节追加，不回改前文。）
