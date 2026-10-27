# 小步推进方案：任务 21 四 bank 帧缓存（增量方案）

## 1. 背景与目标

- 对应 `项目方案.md` 任务 21。当前稳定点 **E7**（任务 20 完整版 FAT32 簇链跟随已完成）。
- **本次单一目标**：4 张图同时常驻 SDRAM，切换时只改显示读地址（在帧消隐期提交），**零加载延迟、不撕裂**。
- 采用**增量方案（方案一）**：保留 `frame_read_write.v`（其官方已预留 4 组读/写地址端口），只改上层控制与地址接线；**不**移植教程的 `media_frame_loader/reader/player_control`，**不**删除 `frame_read_write/video_timing_data/video_delay`，**不**新建异步 FIFO IP。
- **本次不做（范围冻结）**：
  - 两张常驻图之间的**真正交叉 fade**（需同时读两个 bank，单读口不支持）→ 留待任务 22；
  - 子目录、长文件名（任务 20 已界定，不回头）；
  - 音频、缩略图等其它任务内容。
- **转场保留口径**：现有 fade 是“淡到黑 → 从黑淡入”，同一时刻只读一个 bank（见 `top` 的 `e2_fade_read_buf_idx` 在黑场点才切换），单读口可支持；reveal/wipe 也只读一个 bank。故转场只需把“buffer 索引”改为“图号(bank)索引”即可继续工作。

## 2. 当前代码事实

### 2.1 帧缓存桥接（`src/user_source/hdl_source/SD/frame_read_write.v`）

- 已含 4 组基地址端口：写 `write_addr_0..3` + `write_addr_index[1:0]`；读 `read_addr_0..3` + `read_addr_index[1:0]`；`write_len/read_len` 为 21 位。
- 内部仅一条写通道（`frame_fifo_write` + `wfifo_32_32_512`）、一条读通道（`frame_fifo_read` + `rfifo_32_32_512`）。**单读口**，无法同一帧周期取两个 bank。

### 2.2 顶层（`src/user_source/hdl_source/top_tf_hdmi_audio.v`）

- 参数：`FRAME_PIXELS=24'd307200`（行 36）、`BUF0_ADDR=0`（37）、`BUF1_ADDR=FRAME_PIXELS`（38）。
- `frame_read_write_m0`（行 704~754）：
  - 读：`read_addr_0=BUF0_ADDR, read_addr_1=BUF1_ADDR, read_addr_2=0, read_addr_3=0`（724~727），`read_addr_index=frame_read_buf_idx`（728），`read_len=FRAME_PIXELS`（729）。
  - 写：`write_addr_0=BUF0_ADDR, write_addr_1=BUF1_ADDR, write_addr_2=0, write_addr_3=0`（742~745），`write_addr_index=write_buf_idx`（746）。
- 显示索引：
  - `frame_read_buf_idx = e2_transition_mode_sync ? e2_fade_read_buf_idx : disp_buf_idx(同步后)`（行 274）。
  - `disp_buf_idx`（sd_card_clk 域）经两级同步为 `e2_disp_buf_sync`（行 362~363）。
  - 帧消隐脉冲 `e2_frame_pulse = e2_vs_d && !vs`（行 275，vs 下降沿=帧起始消隐）。
  - 显示变化检测 `e2_disp_changed`（行 276）驱动 reveal/fade。
- 写完成回传：`frame_write_finish`（741）→ ext_mem_clk 域 toggle（行 575~580，`frame_write_toggle_mem`）→ sd_card_bmp 的 `write_finish_toggle`。

### 2.3 播放控制（`src/user_source/hdl_source/SD/sd_card_bmp.v`）

- 端口含 `write_buf_idx/disp_buf_idx`（24~25，2 位 reg）、`write_finish_toggle`（23）。
- 关键寄存器：`img_idx`（显示中图号）、`load_idx`（写入中图号）、`pending_buf_idx`（写入目标 buffer）、`write_buf_idx`、`img_cluster0..3`、`img_found_count`、`bad_image_mask`、`load_busy`、`source_done_seen`、`write_finish_seen`、`load_retry_used`、`next_req_pending`、`first_image_committed`。
- 现状为**按需双缓冲**：
  - 首图写 buffer0（行 638~650，`pending_buf_idx<=0, write_buf_idx<=0`）。
  - 后续 key/轮播：目标 buffer 由 `next_buf_lut(disp_buf_idx, display_valid)` 取“非显示”的另一块（行 652~676）。
  - 写完成且源送完才 `disp_buf_idx<=pending_buf_idx; img_idx<=load_idx`（行 572~585）。
  - 失败重试一次，仍失败置 `bad_image_mask[load_idx]` 并跳到下一张（行 516~540）。
- `next_buf_lut`（行 451~462）即“双缓冲取另一块”函数，**本次删除其用途**。
- 扫描结果在 `scn_scan_done` 时锁存 `img_cluster0..3 / img_file_size0..3 / img_found_count`（行 543~554）。
- 实例：`u_scanner`（712）、`u_chain`（742，`.start_cluster(load_cluster)`）、`bmp_read_m0`（769，`.load_sector(32'd0)`、`.load_file_size(file_size_lut(load_idx))`）、`sd_card_top_m0`（810）。

### 2.4 容量核对

- 每帧 307200 个 32 位字；4 帧 = 1,228,800 字。SDRAM 用户地址 21 位 = 2,097,152 字。**占约 58.6%，放得下**，余约 868k 字。

## 3. 改动步骤（每步独立上板）

### 步骤 1：补齐 4 bank 地址，不改行为

- `top`：新增参数 `BANK0_ADDR=0, BANK1_ADDR=307200, BANK2_ADDR=614400, BANK3_ADDR=921600`（保留/替换 BUF 名）。
- `frame_read_write_m0`：读/写 `addr_0..3` 全部接 BANK0..3（替换 724~727、742~745 的 `0` 常量）。
- 索引仍由现有 `write_buf_idx/frame_read_buf_idx` 驱动（只产生 0/1），**行为不变**。
- 目的：先确认地址常量与接线无副作用。

### 步骤 2：上电顺序装载 4 图到固定 bank

- `sd_card_bmp`：
  - 新增 `bank_valid[3:0]`（成功写完一帧置位；复位/重扫清零）。
  - 扫描完成后进入**顺序装载**：`load_idx` 从 0 递增到 `img_found_count-1`；每次 `write_buf_idx <= load_idx`、`pending_buf_idx <= load_idx`（图号即 bank，**不再取“另一块”**），`load_cluster<=cluster_lut(load_idx)`。
  - 单张成功（源完+写完成）→ `bank_valid[load_idx]<=1`，`load_idx<=load_idx+1`；失败重试一次仍失败 → 置 `bad_image_mask[load_idx]`，`bank_valid` 保持 0，继续下一个。
  - 第一张**好图**装载完成即提交显示（`disp_buf_idx<=该图号; img_idx<=该图号; display_valid<=1`），其余 bank **后台继续装载**。
  - 全部尝试完置 `all_resident`。
- 本步显示路径仍只显示已提交的首图（暂不把显示切到后台新 bank）。
- 后台装载写的是其它 bank，不碰显示 bank；写优先仲裁可能在预载的几秒内造成极轻微读 underflow，靠读 FIFO 吸收（验收时重点看是否有卡顿）。

### 步骤 3：显示按图号读固定 bank，帧消隐提交、零延迟切图

- `sd_card_bmp`：常驻后 key_next/轮播不再发起加载，只计算 `req_index = next_good_index(...)`（跳过坏/缺），输出一个“请求显示图号”。
- `top`（video 域）新增小锁存：
  - 把 sd 域 `req_index`、`bank_valid` 经电平/2FF 同步到 video 域。
  - 在每个 `e2_frame_pulse`：若请求 bank 有效且 ≠ 当前，则 `video_active_bank <= req_index`。
  - 用 `video_active_bank` 作为显示侧 bank 索引（替代直接跟随的 `e2_disp_buf_sync`），使现有 reveal/fade 逻辑继续可用。
- 效果：切图最坏等一个帧消隐（约 16ms，观感即时），**无 SD 加载延迟、不撕裂**。
- 预载未完成时按 next：允许在“已 valid”的 bank 间即时切换；指向尚未就绪 bank 的请求暂不生效（或等其 valid 后下一帧生效）。

### 步骤 4：坏图/缺图门控 + 转场映射

- 切换目标选择统一走 `next_good_index/prev_good_index`（已具备 bad mask），保证不切到无效 bank；无效请求保持当前帧（任务 10 语义）。
- fade-through-black 与 reveal 的目标/当前索引改用图号(bank)索引（因 bank==图号，基本是同名替换）；确认黑场点切换读 bank 后画面正确。
- 不做真正交叉 fade。

### 步骤 5：拔卡/重插重载与整体验收

- 拔卡：`display_valid`/`bank_valid` 处置沿用任务 12；重插后重新扫描，清 `bank_valid/bad_image_mask`，按固定 bank 重新顺序装载，完成后恢复常驻切换。
- 整体验收（见第 4 节），通过后归档并更新进度，稳定点升 **E8**。

## 4. 验收方式

- **本地语法检查（ModelSim `vlog`，不跑 TD syn/phy/bitstream）**：
  - 编译 SD 目录相关文件（`sd_card_bmp.v`、`fat32_volume_scanner.v`、`fat32_chain_reader.v`、`bmp_read.v` 等）；含安路原语时加 `E:/Anlu/TD_6_2_1/arch/eagle_macro.v`。
  - 建议新增 `sim/tb_resident_control.v`：驱动“扫描完成→顺序装载 4 bank→常驻→发 next 脉冲”，断言：装载阶段写 index 依次=0..3；常驻后 next 只改请求图号、**不再产生 load_start**；坏图被跳过。
- **TD/上板（用户执行）**：每步重新综合/布线/出 bitstream。
  - 步骤 1：四张图/编号/切图/轮播与 E7 完全一致（无回归）。
  - 步骤 2：上电出首图；预载期间无明显卡死/花屏。
  - 步骤 3：四图**瞬时切换**、内容完整、无撕裂错位；快速连按 next 不丢帧、不回跳。
  - 步骤 4：含坏图/缺图时不切到坏槽、保持上一帧；fade（淡到黑再淡入）与 reveal 正常。
  - 步骤 5：拔卡/重插后恢复，四图常驻与零延迟依旧；亮度对比度、方向、OSD、编号无回归。
- **判据不下调**：零加载延迟、不撕裂、四图常驻三条必须同时满足。

## 5. 回退点与风险

- 改动前稳定点 **E7**（见 `项目进度.md` 3.1）。任一步异常，回退 E7；步骤 1 仅接线，最安全，作为中途回退锚点。
- 风险与对策：
  1. **控制 FSM 重构是主要风险**：现有加载/重试/恢复/轮播/握手交织。对策：按 5 步小改、每步上板；保留任务 10/12 判据，先仿真控制序列。
  2. **后台预载 vs 显示带宽**：写优先可能瞬时挤占读、产生轻微 stutter。对策：读 FIFO 吸收并上板观察；若不可接受，改为“四图全载完再显示”（启动慢、过程平滑）作为备选，需用户拍板。
  3. **时序裕量**：E7 setup WNS −6.7ns、442 违例端点；新增控制/锁存可能加重。对策：单因素推进，必要时对 video 锁存路径打拍。
  4. **单读口约束**：仅支持淡到黑/reveal，真正交叉 fade 留任务 22（已确认）。
  5. **CDC**：req_index/bank_valid 跨域用电平同步 + 帧消隐单点提交，避免亚稳与中途切换。

## 6. 任务过程记录

（执行中追加：实际改动、检查结果、上板现象、与方案偏离及原因。）
