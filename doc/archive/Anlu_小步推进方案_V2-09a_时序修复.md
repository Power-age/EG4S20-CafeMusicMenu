# Anlu 小步推进方案 V2-09a 补丁：hold 时序违例修复（HWNS −1.046ns）

> 状态：**已闭环（2026/10/17 14:31）。** 时钟级双向 set_false_path 从 syn_1 重跑后 phy HWNS 由 −1.046 回正为 **+0.014ns（0 hold 违例，连加密 IP 复位那条 −0.005 也随布局回正）**；SWNS −6.699、BRAM36、DSP13 不变；phy LUT16162/REG9359（较 14:31 前 16157/9352 微增 5/7，为约束改后布局重打包所致，资源账仍合格）。
> 历程：根因已彻底查明，方案从"寄存器级 false_path"升级为"时钟级双向 false_path"，timing.sdc 第 8 节改定后一次重跑成功。
> - 第一次失败：寄存器级 `set_false_path` 用 `get_regs {u_vol_gain/vol_reg[*]}` 因**缺少 `-hier`** 直接报错（`USR-8159 CRITICAL-WARNING ... fails`），整条约束被丢弃，HWNS 不变。
> - 进一步查明：即使把 `get_regs` 改对，寄存器级也只能覆盖 4 条违例中的 **2 条**；另外 2 条终点是综合器高扇出复制 + SLICE 打包在跨域方向呈现的"假路径"，终点随布局变化、无法稳定枚举。
> - 最终采用：**时钟级双向 `set_false_path`（clk↔video_clk）**，与官方例程 `media_player_promax_top.sdc` 第 49 行同款；已逐条核对两域间真实跨域信号均有两级同步器。
>
> 触发：V2-09a（自动淡出/淡入 + 横幅迁移，队友已实现并上板，功能正常）跑完 phy 后 HWNS 由 E13 的 **+12ps 转为 −1.046ns**。
> 本方案对应 V2-09 主方案 §1（第 25 行）门禁："若 09a 后 slices ≥91% 或 HWNS 转负，暂停 09b，先处理时序。"**09b 上沿羽化一律暂停，先把本步闭环。**
> 本步**只改 SDC 约束，不改任何 RTL**。

---

## 1. 现象与数字（phy_1，2026/10/17，route.qor / final_timing.rpt）

| 指标 | E13（V2-08 基线） | V2-09a | 变化 |
|---|---|---|---|
| Hold WNS（HWNS） | **+0.012ns** | **−1.046ns** | 转负（本步要修） |
| Hold TNS（HTNS） | 0 | −3.846ns | 4 个跨域端点违例 |
| Setup WNS（SWNS） | −6.699ns | −6.699ns | 不变（125MHz SDRAM 既有遗留，本步不碰） |
| slices | 8737（89.15%） | 9109（**92.95%**） | +372，布局更拥挤 |
| LUT / REG（phy） | 15537 / 9212 | 16157 / 9352 | +620 / +140 |
| BRAM9K / DSP | 36 / 13 | 36 / 13 | 不变（资源账合格） |

上板功能队友已确认正常（淡出/淡入、状态栏、音乐、切图均正常）。

**Clock Summary 归属（final_timing.rpt 第 48~55 行，权威判据）**：

| 时钟 | 频率 | HWNS（hold） | 说明 |
|---|---|---|---|
| clk4 = **clk** | 50MHz | **−1.046（HTNS −3.841，4 端点）** | 全部来自 video_clk→clk 跨域，本步目标 |
| clk1 = video_clk | 25MHz | **−0.005（1 端点）** | 加密 HDMI IP 复位 removal，无法改，见 §2.4 |
| clk0 sd_card_clk | 100MHz | +0.014 | 正 |
| clk2 ext_mem_clk | 125MHz | +0.016（setup −6.699） | hold 正，setup 是 SDRAM 遗留 |
| clk3 audio_mclk | 12.3MHz | +0.368 | 正 |
| clk5 hdmi_5x_clk | 125MHz | +0.359 | 正 |
| clk→clk 域内部 | 50MHz | **+0.329** | 正，切掉跨域后 clk 域自身 hold 不受影响 |

> 注：报告里还能看到 −6.018 / −3.851 / −2.288 等负 slack，它们属于**其他时钟组的 setup**（如 clk6 SWNS −3.851）或已被 set_clock_groups 豁免的跨域，**不计入 hold WNS**；Clock Summary 已明确全局 HWNS 只由 clk4 的 −1.046 决定。

---

## 2. 根因定位（phy_1/final_timing.rpt，`Path Group: video_clk -> clk`，第 10497~11630 行）

### 2.1 4 个 hold 违例端点（Min Paths，第 11074 行起，全部 Logic Level 0、fast corner）

| Slack | 起点寄存器（源，video_clk 25MHz） | 终点寄存器（目的，clk 50MHz） | 终点引脚 |
|---|---|---|---|
| **−1.046** | `u_vol_gain/vol_reg[1]_syn_11` | `sd_card_bmp_m0/u_track_controller/target_index_reg[0]_syn_487` | .mi[0] |
| −0.981 | `u_vol_gain/vol_reg[0]_syn_15` | `vol_lvl_c1_reg[2]_syn_4` | .mi[0] |
| −0.929 | `u_vol_gain/vol_reg[0]_syn_17` | `vol_lvl_c1_reg[3]_syn_4` | .mi[1] |
| **−0.885** | `u_vol_gain/vol_reg[0]_syn_13` | `sd_card_bmp_m0/u_track_list/valid_mask_reg[5]_syn_11` | .mi[0] |

四个 slack 之和 −1.046−0.981−0.929−0.885 = **−3.841**，与 Clock Summary 的 HTNS −3.841 精确吻合，即 hold 违例就这 4 条、全部在 video_clk→clk 方向。

### 2.2 两类终点：2 条真同步器 + 2 条 SLICE 打包"假路径"

**(a) 真 CDC 同步器（2 条，终点 vol_lvl_c1）**
- 源：`audio_volume_gain u_vol_gain`（`.clk(video_clk)`，top 1035）内部音量档 `reg[3:0] vol`（`audio_volume_gain.v:29`），输出 `vol_level_a`。
- 目的：top 第 1101 行两级同步器第一级 `vol_lvl_c1`（`always @(posedge clk) vol_lvl_c1 <= vol_level_a; vol_lvl_c2 <= vol_lvl_c1;`）。
- RTL 中 `vol_level_a` **唯一**消费就是 `vol_lvl_c1`（grep 全工程：wire 967、输出 1042、使用 1101）。

**(b) SLICE 打包假路径（2 条，终点 target_index / valid_mask）**
- RTL 里 `target_index` 由 `first_valid(valid_mask)`/`next_valid`/`prev_valid` 驱动（`track_controller.v:155/166/167`），`valid_mask` 是 track_list 输出，**二者与音量 `vol_level` 没有任何逻辑连接**。
- 但综合器对高扇出的 `vol_reg` 做了寄存器复制（`vol_reg[0]` 被复制成 `_syn_13/_syn_15/_syn_17` 多个物理 FF，net `vol_level[0]` 扇出达 18），并把 `vol_lvl_c1` 与 `target_index/valid_mask` 等 FF 打包进同一 SLICE；其 D 输入 LUT 被报告为连到 `vol_reg` 副本（`.mi[0]/.mi[1]` 即 SLICE 内 LUT 输入）。STA 对这些零逻辑级连接保守地按 video_clk→clk 计 hold，于是出现"音量驱动曲目索引"的假路径。
- 反向组 clk→video_clk（第 12484 行起）同样能看到 `target_index/add0 → volv_meta` 的对称假路径，互为印证。
- 这类假路径的**终点随每次布局/打包变化**（今天是 target_index/valid_mask，重编译可能变成别的 SLICE 邻居），靠枚举终点的寄存器级约束无法稳定覆盖。

### 2.3 为什么是约束缺失，不是 RTL 功能 bug

1. `video_clk` 由**独立 video_pll** 产生（25MHz），`clk` 是外部 50MHz 晶振（video_pll 的参考）；PLL 输出相对参考输入相位不可预测，二者物理异步，标准 CDC 做法是"两级同步器 + 对跨域路径不做时序检查"。
2. 所有真实跨域信号 RTL 都已写两级同步器（见 §3.2），音量档是慢变电平，功能从 V2-08 起一直正常。
3. `timing.sdc` **没有把 clk 与 video_clk 设为异步**：
   - L63~65 只把 `audio_mclk` 与 `{clk, video_clk, hdmi_5x, sd_card, ext_mem}` 分开（clk 与 video_clk 同组，仅一起对 audio 异步）；
   - L76~78 只把 `{video_clk, hdmi_5x}` 与 `{sd_card, ext_mem}` 分开（**clk 不在其中**）；
   - 于是 clk 与 video_clk 被当作相关时钟做同步 hold 检查（报告 Type 标为 "Same Domain"）。
4. E13 时器件空闲，布线把同步器拉到刚好 +0.012ns（贴 0）；V2-09a 使 slices 升到 92.95%，相关寄存器被布得更近、数据走线变短，hold 转负。**约束缺失是因，布局拥挤是触发条件**，不是 V2-09a 逻辑错误，也无需打拍/重构。

### 2.4 第 5 个端点（video_clk 域 −0.005）：加密 HDMI IP 复位，量极小、无法改

- Slack **−0.005ns**（5ps），Check Type 为 **removal**（复位恢复，属 hold 类），源 `u_hdmi_1_4b_transmitter_core_wrapper/u0_reset_sync/O_sync_reset_reg`，终点 `…/u2_hdmi_tmds_encode/S_data_island_code_reg[4].sr`，全在加密 IP `*.enc.v` 内部。
- 复位树 fanout 大、fast corner 下 5ps 抖动，E13 时为正、09a 拥挤后微负。**不碰加密 IP（规则），无法 RTL 修复**；重跑布局大概率回正。本步只跟踪，不处理。

---

## 3. 最终修复方案：时钟级双向 set_false_path

### 3.1 为什么放弃寄存器级（选项 1）

1. **第一次尝试直接失败**：`get_regs {u_vol_gain/vol_reg[*]}` / `{vol_lvl_c1_reg[*]}` 缺少 `-hier`，TD 报
   `USR-8159 CRITICAL-WARNING: Command set_false_path ... fails`（syn_1/run.log:741、phy_1/run.log:164/361/915），整条约束被丢弃，故 `exception.timing` 中无此条、HWNS 与资源数字一字不差。
   - 官方例程 `media_player_promax_top.sdc` 中所有 `get_regs` 都带 `-hier`（如 `get_regs -hier {*/s1}`、`get_regs -hier {u_subtitle_frame_commit/dst_text[*]}`）。
2. **即使补对 `-hier`，寄存器级也只覆盖 2 条**：终点只有 `vol_lvl_c1[2]/[3]` 两条匹配，`target_index/valid_mask` 两条假路径不匹配，HWNS 仍会留下 −1.046；且不能用裸 `-from vol_reg`（会误切 `audio_volume_gain` 内同 video_clk 域的 `vol→gain_q15→prod_l/prod_r` 增益乘法，`audio_volume_gain.v:44-47`）。
3. 假路径终点随布局变化，逐条 `set_false_path -to ...` 治标不治本。

### 3.2 时钟级双向 set_false_path（已写入 timing.sdc 第 8 节）

```tcl
set_false_path -from [get_clocks {video_clk}] -to [get_clocks {clk}]
set_false_path -from [get_clocks {clk}] -to [get_clocks {video_clk}]
```

- 与官方例程 `media_player_promax_top.sdc:49` 的 `set_false_path -from [get_clocks {pixel_clk}] -to [get_clocks {sys_clk}]` 同款。
- 一次覆盖 clk↔video_clk 两个方向的**全部**跨域路径（真同步器 + 打包假路径），不随布局/重命名变化；
- 两个域**内部**同域路径完全保留（含 `vol→增益乘法`、HDMI 发送、数码管扫描等）；
- 只切 clk 与 video_clk，**不碰 clk 与 sd_card_clk/ext_mem_clk**（sys_pll 同源，沿用既有相关分析）；
- 用 `set_false_path -from/-to [get_clocks]` 而**非 `set_clock_groups`**：L63~65 已把 clk、video_clk 写在同一 `-group`，再新增一条把二者分到不同异步组的 `set_clock_groups` 可能产生时钟组关系冲突；时钟级 `set_false_path` 是叠加 exception，不与既有 set_clock_groups 冲突，更稳。

### 3.3 已逐条核对：clk↔video_clk 真实跨域信号都有两级同步器

| 信号 | 方向 | 两级同步器（top 行号） |
|---|---|---|
| 音量档位 | video→clk | `vol_lvl_c1`→`vol_lvl_c2`（1101） |
| 音量档位（回 video 供 OSD/UI） | clk→video | `volv_meta`→`volv_sync`（531） |
| 当前曲目名 | clk→video | `tkn_meta`→`tkn_sync`（530） |
| 当前显示图号/bank | video→clk | `e2_disp_buf_meta`→`e2_disp_buf_sync`（367/368） |

- 跨域组里出现的其它终点（`target_index/valid_mask/add0/seg_data/header_match/e2_disp_buf/right_shift2`）均为 §2.2 所述 SLICE 打包呈现或同步器之后的同域段，非裸奔跨域；
- 这些都是慢变电平（音量、图号、曲目名、状态），setup 裕量 14~17ns，硬件一直正常；切跨域时序检查符合 CDC 规范，**不会改变任何功能**。

### 3.4 不做的事（防止混入第二因素）

- 不改任何 RTL、不打拍、不改 ui_visible_ctl / overlay（V2-09a 已上板正常）。
- 不处理 setup 遗留 SWNS −6.699（125MHz SDRAM），与本 hold（CDC 零逻辑级）是独立问题。
- 不动加密 IP 的 −0.005ns removal。
- 不做 V2-09b 上沿羽化（slices 92.95% 门禁未解除）。

---

## 4. 执行步骤（SDC 已改完，由你在 TD 跑，我不综合）

1. timing.sdc 第 8 节已改定（时钟级双向 set_false_path）。
2. 在 TD 中**从 syn_1 重跑**（含 phy_1、bitgen），让约束全程生效。
3. 跑完发我 phy_1 的 `final_timing.rpt` 与 `…_exception.timing`，或直接在 Tcl Console 跑
   `report_timing_summary -report_type min -viol_only` 截图。
4. 上板快速回归：状态栏、5 秒淡出/操作唤醒、音乐、切图、音量加减、数码管音量显示（音量档走第二级 vol_lvl_c2，不受 false_path 影响，应随加减更新）。

---

## 5. 验证约束是否生效（关键）

重跑后两处确认：

1. `phy_1/…_exception.timing` 的 Status of timing exceptions 应出现 **2 条时钟级 set_false_path**（video_clk→clk、clk→video_clk），且不再有 `USR-8159 ... fails`（查 `syn_1/run.log`、`phy_1/run.log`）。
2. `final_timing.rpt` 中：
   - Path Group `video_clk -> clk` 与 `clk -> video_clk` 整个组不再参与时序（路径被移到 ignored/不出现）；
   - Clock Summary 的 clk4 HWNS 由 −1.046 变为其**域内部**值（约 +0.329ns，正）；
   - 全局 HWNS 仅剩 video_clk（clk1）的 −0.005（加密 IP 复位，重跑也可能回正到 ≥0）。
3. 预期：**Hold WNS ≥0，或仅余 −0.005ns（5ps，可接受）**；Setup 仍 −6.699ns（SDRAM 遗留，符合预期）；LUT/REG/BRAM/DSP 不变（只改约束，未改网表）。

> 若时钟级 set_false_path 因某种原因未被识别（exception.timing 无此条），兜底改用语义等价的
> `set_clock_groups -asynchronous -group [get_clocks {clk}] -group [get_clocks {video_clk hdmi_5x_clk}]`，
> 但需先确认 TD 不报与 L63~65 同组的冲突；通常不会走到这一步。

---

## 6. 验收判据（不满足不算完成）

- [x] phy Hold WNS 不再含 video_clk→clk 的 4 条违例（clk4 HWNS 由 −1.046 回正为 **+0.014**）；
- [x] 加密 IP 复位 −0.005 那条也随布局回正（实际全局 HWNS +0.014，无需接受负值）；
- [x] Setup SWNS 仍 −6.699ns、BRAM9K=36、DSP=13、BRAM32K=0；phy LUT16162/REG9359（约束改后布局重打包，较前 16157/9352 微增 5/7，未改网表逻辑，资源账合格）；
- [ ] 上板：状态栏淡出/淡入、音乐、切图、音量加减、数码管音量显示全部正常无回归（待用户确认）；
- [x] 仅改动 timing.sdc，无 RTL 改动（单因素，便于对照）。

---

## 7. 风险与回退

- **风险**：时钟级切法覆盖 clk↔video 全部跨域。已通过 §3.3 核对所有真实跨域均有两级同步器，风险低；仍以 §6 上板回归兜底。
- **回退**：删除 timing.sdc 第 8 节两条 set_false_path 即恢复 V2-09a 现状（HWNS −1.046、功能正常）。

---

## 8. 任务过程记录

- **2026/10/17 初**：读 phy_1 route.qor/final_timing.rpt/exception.timing/timing.sdc 定位根因（CDC 约束缺失），建立寄存器级精准 false_path 方案（选项 1），用户确认后写入 timing.sdc。
- **2026/10/17 第一次重跑**：用户从 syn_1 重跑（13:54 syn、13:55 phy/bitgen）后 HWNS 仍 −1.046、资源数字一字不差。按用户要求先补 V2-09a 文档（项目进度 5.30 等），时序挂起。
- **2026/10/17 复查（本次）**：
  1. `syn_1/run.log:741` 与 `phy_1/run.log:164/361/915` 发现 `USR-8159 CRITICAL-WARNING: Command set_false_path ... fails`，证实旧约束因 `get_regs` 缺 `-hier` 整体失败（非静默、是命令报错）。
  2. 对比官方例程 `doc/完赛系列/.../media_player_promax_top.sdc`，所有 `get_regs` 均带 `-hier`；并确认 `[*]` 须配合 `-hier`。
  3. 读 gate.timing（syn 阶段名为 `vol_reg[0..3]`、`vol_lvl_c1_reg[0..3]`）与 final_timing.rpt（phy 阶段带 `_syn_N`，`vol_reg[0]` 被复制为 `_syn_13/15/17`），确认寄存器级即使修正也只覆盖 2 条，另 2 条终点为 target_index/valid_mask。
  4. 用 Clock Summary 确认全局 HWNS −1.046/HTNS −3.841 全部归在 clk4，且 4 条 slack 之和恰为 −3.841；clk→clk 域内部 hold +0.329；−6.018/−3.851/−2.288 是他组 setup 或已豁免跨域，不计入。
  5. 核对 RTL：vol_level_a 唯一消费 vol_lvl_c1；target_index 由 valid_mask 驱动、与音量无关；确认 4 个端点的源都是 vol_reg 副本（高扇出复制 + SLICE 打包假路径）；clk↔video 真实跨域信号（音量/曲名/图号）均有两级同步器。
  6. 结论：把第 8 节从寄存器级改为**时钟级双向 set_false_path**（clk↔video_clk），已写入 timing.sdc，等待用户重跑验证。
- **2026/10/17 14:30~14:31 重跑成功（闭环）**：用户从 syn_1 重跑（14:30 syn、14:31 phy/bitgen）。phy **HWNS 由 −1.046 回正为 +0.014ns（0 hold 违例）**；SWNS −6.699 不变；BRAM9K 36、BRAM32K 0、DSP 13 不变；phy LUT16162/REG9359（较前 16157/9352 微增 5/7，约束改后布局重打包，非网表逻辑变化）。syn LUT15806/REG9220 不变。即 V2-09 门禁中的"HWNS 转负"已解除；slices 仍约 92.95%（≥91% 门禁条件仍成立），**V2-09b 上沿羽化是否继续仍需先评估资源**。
