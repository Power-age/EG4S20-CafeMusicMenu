# 小步推进方案：任务 21 步骤 2 —— 上电顺序装载 4 图到固定 bank

> 上位方案：`Anlu_小步推进方案_任务21.md`。当前稳定点 E7（任务 20 完整版 FAT32 簇链跟随）。
> 步骤 1（补齐 4 bank 地址接线、行为不变）已完成，并于 2026/10/05 12:10 bitstream 上板现象正常。
> **状态：步骤 2 已实施并于 2026/10/05 上板通过（4 图常驻固定 bank，画面完整、切图键本步无反应）。**

## 1. 本步单一目标

扫描完成后自动按 PIC1→PIC4 顺序逐张写入**固定 bank（图号 = bank 号）**，不再使用"非显示另一块"双缓冲；第一张好图写完即提交显示，其余后台继续装载；全部尝试完置 `all_resident`。

**本步切图键故意暂不生效**（步骤 3 才实现帧消隐零延迟切换）。

**范围冻结**：不做真正交叉 fade、不做子目录/LFN、不碰音频/缩略图；不改 frame_read_write / video_timing_data / video_delay，不新建异步 FIFO IP。

## 2. 改动清单（只改 sd_card_bmp.v，top 仅增量观察接线）

### 改动一：sd_card_bmp.v 新增寄存器与输出端口
- 输出端口 `output [3:0] bank_valid_out`，`assign bank_valid_out = bank_valid`
- 寄存器 `reg [3:0] bank_valid;`、`reg all_resident;`、`reg [2:0] next_load_idx;`

### 改动二：复位 / 拔卡 / 重扫清零
主复位分支、`!sd_init_done` 分支、发起扫描分支三处加入：
`bank_valid <= 4'd0; all_resident <= 1'b0; next_load_idx <= 3'd0;`

### 改动三：第二次失败分支简化
第一次失败重试保持不变；第二次失败只置 `bad_image_mask[load_idx]`、清 load_busy / source_done_seen / write_finish_seen、`load_retry_used<=0`；删除 next_good / next_buf 跳转装载（游标自动走到下一位置）。

### 改动四：成功提交分支
- 无条件 `bank_valid[load_idx] <= 1'b1`，清 load_busy / seen / load_retry_used
- 仅当 `!first_image_committed`（第一张好图）才提交显示：`disp_buf_idx<=load_idx; img_idx<=load_idx;` 显示区域<=pending、`display_valid<=1; first_image_committed<=1`
- 之后后台 bank：显示完全不动

### 改动五：顺序装载触发（替换原首图/手动/自动三个分支）
- 条件 `scan_done && !all_resident && bmp_ready && !load_busy && next_load_idx < img_found_count`：
  load_idx / pending_buf_idx / write_buf_idx <= next_load_idx[1:0]，load_cluster<=cluster_lut(next_load_idx)，load_start_pulse，load_busy=1，清 seen/retry/next_req/auto，`next_load_idx <= next_load_idx+1`
- 否则 `next_load_idx >= img_found_count && !load_busy`：`all_resident<=1`

### 改动六：顺序阶段屏蔽手动/自动
- key_auto 开关条件加 `all_resident &&`
- 旧手动/自动装载分支由改动五删除；next_req_pending 在顺序触发中清 0

### 改动七：top 观察接线（纯增量）
- 新增 `wire [3:0] bank_valid_wire;` 接 sd_card_bmp `bank_valid_out`
- 新增 seg_decoder 把 bank_valid 转七段码
- seg_scan 的 seg_data_4（原空闲全灭）改为显示该码

## 3. 本地验证（不跑 TD syn/phy/bitstream）

1. `iverilog -g2001 -Wall -i` 编译 sd_card_bmp.v（遇安路原语加 `arch/eagle_macro.v`）
2. tb / Python 模型断言：扫描后 write_buf_idx 依次 0,1,2,3；坏图位置 bank_valid 对应位不置、游标继续；第一张好图提交显示；最终 all_resident=1

## 4. 上板预期与验收

1. 上电出 PIC1；数码管第 4 位几秒内 1→3→7→F 并稳定 F；期间画面保持 PIC1，重点观察后台装载有无明显卡顿（读 FIFO 应吸收）
2. 本步切图键无反应属正常（步骤 3 恢复）
3. 坏图：如 PIC2 坏，数码管走 1→5→D（跳过 bit1），第一张好图仍提交、不卡死、不黑屏

**边界**：若 PIC1 就坏，第一张好图出现时 disp 0→该 bank，会走一次现有转场（黑屏揭示/淡入），属预期，步骤 4 细化。

**备选**：若后台装载卡顿不可接受，改为"四图全装完再显示"（启动慢但平滑），由用户拍板。

## 5. 回退点与风险

- 回退点：步骤 1 上板通过版本（E7 + 4 bank 地址接线）。异常时优先整体回退 sd_card_bmp.v 与 top 的步骤 2 改动。
- 风险：① 装载 FSM 重构为主要风险，靠仿真控制序列 + 单步上板；② 后台预载 vs 显示带宽，读 FIFO 吸收，必要时切备选；③ CDC：bank_valid 为慢变电平，数码管直接显示可接受。

## 6. 任务过程记录

- 2026/10/05：用户确认步骤 2 方案，开始实施。改动前完整备份工程至 `test/Project_backup_20261005`。
- 2026/10/05：完成 sd_card_bmp.v 改动一至六、top 改动七。
- 2026/10/05：ModelSim `vlog` 编译 SD 目录全部 19 个源文件 + eagle_macro：**0 error 0 warning**。
- 2026/10/05：新增 `sim/tb_step2_resident.v`，用 force 行为化下游、真实跑顺序装载控制 FSM，两场景通过：
  - 场景A（4 张全好）：装载/写索引依次 0,1,2,3，最终 bank_valid=4'hF、all_resident=1、首图 idx0 提交显示（display_valid=1、disp_buf=0）。
  - 场景B（idx1 坏）：idx1 重试一次后被跳过（bad_mask=4'b0010、bank_valid=4'hD），游标继续装完 idx2/3、all_resident=1，首图 idx0 仍正常提交。
  - 调试要点：driver 不能只看 load_busy 电平（一张成功后主 FSM 立即自动发起下一张），须按当前图号 dli 的 bank_valid[dli]/bad_mask[dli] 判定完成，并在 D0 用 load_idx 变化识别新图。
- 2026/10/05：`vlog` 编译 hdl_source 全部 46 个源文件：**0 error**；83 warning 全部来自既有加密 IP（hdmi_1_4b_transmitter_core_wrapper.enc.v 80、sdram.v 1、sdr_init_ref.enc.v 1），本次改动的 top / sd_card_bmp **0 warning**。
- 未执行 TD syn / phy / bitstream；步骤 2 待用户上板按第 4 节验收（重点看后台装载期间画面有无明显卡顿；本步切图键故意无反应，步骤 3 恢复）。
