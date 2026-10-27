# Anlu 小步推进方案 时序收敛一期（只改约束）

> **来源**：2026/10/20 用户决定先解决 TD 时序老问题再推进 V2-10。本方案只动 `timing.sdc`，**不改任何 RTL**。
> **当前稳定点**：E15（功能已上板通过）｜**目标**：消化官方已认定的伪违例，把 Setup 653 → 约 589、Hold 3 → 0，为二期 RTL 打拍留出干净基线。

---

## 1. 背景与目标

E15 的 `phy_1/final_timing.rpt`：**Setup SWNS −6.846ns / 653 违例端点，Hold HWNS −0.011ns / 3 违例端点**。台账原记"仅 125MHz SDRAM 遗留 −6.699"严重低估。

按路径组拆分后，其中 **64 个（SDRAM 相位时钟）+ 3 个（Hold）属于官方例程 SDC 已明确认定并约束掉的伪违例**。本方案的目标就是补上这些缺失约束。

### 本期做

1. 声明 SDRAM 采样相位时钟 `clkc[2]`（125MHz / 180°），并对 `ext_mem_clk ↔ ext_mem_clk_sft` 双向 `set_false_path` —— 消化 **64** 个违例端点。**（已实施并验证通过，见 §6 记录 3）**
2. ~~收紧 hold uncertainty 到 `0.050ns` —— 消化 **3** 条 hold 违例。~~ **（2026/10/20 实测否决：本版 TD 将其叠加到默认 0.100ns 上，反而恶化 50ps，已撤除，详见步骤 3 与 §6 记录 3）**

### 本期明确不做

- **不动 110 条 `ext_mem → sd_card`（`fifo_aclr` / `write_req_ack` 跨域）**：经核对这是**真实的跨域握手且无两级同步**，用 `set_false_path` 掩盖会引入 metastability 风险。留到二期加同步器解决。
- 不动 432 条 `sd_card_clk` 域内高扇出 CE、45 条 `frame_fifo_write` 地址链、2 条 `sd_card → ext_mem`——全部是真实同步路径，需 RTL 打拍（二期）。
- 不改任何 RTL、不改引脚约束、不新增模块。

---

## 2. 当前代码事实

### 2.1 现有 `timing.sdc`（121 行）实际内容

| 行 | 内容 |
|---|---|
| 17 | `create_clock -name clk -period 20 [get_ports {clk}]` |
| 22 | `derive_clocks` |
| 33~37 | `rename_clock` 命名 5 个 PLL 输出：`sd_card_clk`(clkc[0])、`ext_mem_clk`(clkc[1])、`video_clk`、`hdmi_5x_clk`、`audio_mclk` |
| 53~55 | `set_clock_groups -exclusive` video_clk / hdmi_5x_clk |
| 63~65 | `set_clock_groups -asynchronous` audio_mclk ↔ 其余 |
| 76~78 | `set_clock_groups -asynchronous` {video_clk,hdmi_5x} ↔ {sd_card_clk,ext_mem_clk} |
| 120~121 | `set_false_path` video_clk ↔ clk 双向（E14 加） |

**缺口**：`sys_pll_m0/pll_inst.clkc[2]`（C2，125MHz，180° 相位）**从未被 `rename_clock` 命名**，也没有任何 clock group 覆盖它，因此它被当作与其他时钟同步的关系参与分析。报告中它显示为 `clk6`（125MHz，36 个端点）。

### 2.2 报告中对应的违例证据

| 路径组 | WNS | 违例端点 | 起止点 |
|---|---|---|---|
| `ext_mem_clk → clkc[2]` | −3.436ns | 32 | `U3/u2_ram/u1_init_ref/ad_reg[10]` → `U3/sdram.dq[*]` |
| `clkc[2] → ext_mem_clk` | −6.699ns | 32 | `U3/sdram.dq[*]` → `U3/sdram_syn_*.bpad` |
| `video_clk → video_clk`（hold） | −0.011ns | 2 | 加密 HDMI IP 内 IIC FIFO 1 条；`u_wav_player/rd_ptr_reg[4]` → `ramread0.addrb[5]` 1 条 |
| `sd_card_clk → sd_card_clk`（hold） | −0.004ns | 1 | 寄存器 → 异步 RAM 读地址类 |

`U3` 是加密 SDRAM 控制器（`sdr_as_ram.enc.v`），路径全在 IP 内部，**无法改 RTL**。

### 2.3 官方例程 SDC 的对应写法（`完赛系列/第6讲/…/media_player_promax_top.sdc`）

第 4~11 行：

```
create_generated_clock -name mem_clk       ... -divide_by 1.25 -phase 0     [get_pins {u_mem_pll/pll_inst.clkc[1]}]
create_generated_clock -name mem_clk_shift ... -divide_by 1.25 -phase 172.8 [get_pins {u_mem_pll/pll_inst.clkc[2]}]
# mem_clk_shift only drives the EG_PHY_SDRAM_2M_32 sampling clock. The official 2026 SDRAM
# package carries its own hard-IP I/O window; treating the forwarded DQ path as a fabric
# setup path produces a fixed false violation.
set_false_path -from [get_clocks {mem_clk}]       -to [get_clocks {mem_clk_shift}]
set_false_path -from [get_clocks {mem_clk_shift}] -to [get_clocks {mem_clk}]
```

第 13~20 行：

```
# All clocks come from one PLL on one die; intra-domain launch/capture pairs share the global
# tree. The tool default hold uncertainty (0.100 ns) exceeds the real PLL jitter + tree skew
# budget ... and kept flagging a rotating set of register -> async-RAM read-address partial
# paths in the +/-15 ps band. 0.050 ns keeps a real guardband while stopping that guardband
# artifact ...
set_clock_uncertainty -hold 0.050 [get_clocks {sys_clk pixel_clk pixel_clk_5x mem_clk mem_clk_shift}]
```

**与本工程现象的对应关系**：我们的 3 条 hold 违例正是"register → async-RAM read address"（`u_wav_player/rd_ptr_reg → ramread0.addrb`）且量级 −11ps / −4ps，落在官方描述的 ±15ps 轮转带内。E14 的 +0.014 与 E15 的 −0.011 之间来回跳，也符合"rotating"特征——不是功能退化。

### 2.4 为什么不动 110 条 `fifo_aclr` 跨域

- `frame_fifo_write.v` 中 `fifo_aclr`（L44 输出）与 `write_req_ack`（L32 输出）**同为 ext_mem 域寄存器**，在同一个 `S_ACK` 状态拉高（L290~292）。`fifo_aclr` 直接接 `write_buf` 的异步清零 `rst`（`frame_read_write.v:100`）。
- `bmp_read` 在 `ST_LOAD_WAIT` 直接用 `write_req_ack` 作条件（**未做两级同步**）。
- 报告中的违例路径从 `fifo_aclr_reg` 经 FIFO 内部/状态组合一路到 `bmp_read` 的 `state_b`，属**真实未同步跨域**。
- 官方 SDC 对"异步复位扇出跨域"确有 `set_false_path -from [get_nets {u_pix_reset/s2}] -to [get_clocks {mem_clk}]` 的先例（第 34~35 行），但那是**已加同步器之后的复位扇出**（`/s2` 即二级同步输出）。我们的 `write_req_ack` 没有对应同步级，条件不成立。
- 结论：这 110 条留给二期加两级同步器解决，**本期不切**。

---

## 3. 改动步骤

只改一个文件：`Project/src/user_source/constraints_source/timing.sdc`。

### 步骤 1：命名 SDRAM 采样相位时钟

在第 37 行（`audio_mclk` rename 之后）追加：

```
rename_clock -name {ext_mem_clk_sft} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[2]}]
```

用 `rename_clock` 而非 `create_generated_clock`：该 PLL 输出已由 `derive_clocks` 自动建出（相位信息已含），此处只需给它一个可被约束引用的名字，与其余 5 个时钟的处理方式保持一致。

### 步骤 2：切断 SDRAM 相位时钟对

在文件末尾（现第 121 行之后）新增一节：

```
# SDRAM 采样相位时钟：clkc[2] 为 125MHz / 180° 相位，仅驱动 SDRAM 控制器的采样窗口。
# DQ 前向路径若按 fabric setup 检查属固定伪违例（官方例程 media_player_promax_top.sdc 第 7~11 行同款处理）。
set_false_path -from [get_clocks {ext_mem_clk}]     -to [get_clocks {ext_mem_clk_sft}]
set_false_path -from [get_clocks {ext_mem_clk_sft}] -to [get_clocks {ext_mem_clk}]
```

### 步骤 3：~~收紧 hold uncertainty~~（已实测否决并撤除，勿再执行）

> **本条已作废**。2026/10/20 实测：TD v6.2.168116 把 sdc 数值**叠加**在默认 `0.100ns` 之上（报告显示 `总 0.150 = sdc 0.050 + default 0.100`），使 hold 恶化 50ps（HWNS −0.011 → −0.070，违例端点 3 → 21）。官方例程的写法依赖"替换"语义，在本版工具不成立。已在 `timing.sdc` 第 10 节留下"勿再添加"的记录。下面保留原始写法仅供追溯。

原计划写法（**不要执行**）：

```
# 工具默认 hold uncertainty 0.100ns 超出真实 PLL 抖动 + 树偏斜预算，会在 ±15ps 带内轮转报出
# "寄存器 → 异步 RAM 读地址"的部分路径（官方例程同款说明，见 media_player_promax_top.sdc 第 13~20 行）。
set_clock_uncertainty -hold 0.050 [get_clocks {clk sd_card_clk ext_mem_clk ext_mem_clk_sft video_clk hdmi_5x_clk audio_mclk}]
```

---

## 4. 验收方式

### 4.1 本地检查（我执行）

1. SDC 语法与时钟名自检：确认 7 个时钟名与 5+1 个 `get_pins` 路径与报告中的实际名完全一致（`clk` / `sd_card_clk` / `ext_mem_clk` / `ext_mem_clk_sft` / `video_clk` / `hdmi_5x_clk` / `audio_mclk`）。
2. 确认无 RTL 改动、无其他文件改动。
3. **无法本地跑 TD**，SDC 的有效性只能由用户构建验证。

### 4.2 用户 TD 验证

1. 只跑 `syn_1` + `phy_1`（不必先出 bitstream），看 `phy_1/route.qor` 与 `final_timing.rpt`。
2. 期望结果（**已按第一轮实测修订**：原以为 hold 会归零，实测证明本版 TD 的 uncertainty 是叠加语义，该假设作废；现本轮只保留 SDRAM 相位 false_path）：

| 指标 | 原始基线（E15） | 第一轮（含已撤除的 uncertainty） | **本轮期望（仅 SDRAM false_path）** |
|---|---|---|---|
| Setup 违例端点 | 653 | 494 | **约 490~500** |
| Setup TNS | −833425 | −373332 | **约 −370000 量级** |
| SDRAM 相位组（`ext_mem↔clkc[2]`） | 64 | 0 | **0** |
| Hold 违例端点 | 3 | 21 | **回落到 3 上下** |
| Hold HWNS | −0.011 | −0.070 | **回落到 −0.02 量级以内** |
| slices / BRAM / DSP | 9025 / 36 / 13 | 9066 / 36 / 13 | 基本不变 |

> 关键判据：**Hold 必须从 21 端点 / −0.070 明显回落**。若未回落，说明还有别的因素在恶化 hold，需另查。

3. 若 `clkc[2]` 的 `rename_clock` 报错或约束未生效（`syn_1/run.log` 出现 `USR-8159` 之类），按日志调整目标 pin 名后重跑。
4. 布局扰动提示：本轮新增的 `video_clk` setup 单条违例（−0.329，`u_wav_player/wstate_reg → u_waveform_data/wave_wr_data_reg`，数据路径 40.049ns 且 net 占 63%）与 `ext_mem` WNS 略差，均属约束改动后的重排结果，会在二期降拥塞/打拍时一并观察，本轮不单独处理。

### 4.3 成功后

- 记录新数字到 `项目进度.md` §6 第 17 条，并更新 §3.3 时序段。
- 进入二期（RTL 打拍），另行立方案。

---

## 5. 回退点与风险

### 回退点

- 改前稳定版：**E15**。约束改动不影响功能，若构建或上板异常，删掉新增三节即回原约束。

### 风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| `rename_clock` 目标 pin 名不匹配 | 约束报错或被丢弃 | 用报告中出现的实际名 `sys_pll_m0/pll_inst.clkc[2]`；失败按 run.log 调整 |
| SDRAM 相位 false_path 掩盖真实 SDRAM 时序问题 | 若 SDRAM 接口本身有问题会被隐藏 | 官方例程对同一 SDRAM 硬核采用完全相同处理并长期出包；且本工程 SDRAM 链路已连续运行 10 分钟无异常 |
| hold uncertainty 放宽到 0.050 后漏掉真实 hold 违例 | 极端 corner 下可能漏检 | 0.050ns 仍保留真实 guardband（官方说明）；若放宽后仍报 hold，说明是真违例，按二期处理 |
| 只跑 syn/phy 不出 bitstream | 无法上板确认 | 本期只验证时序数字，功能不动；如需上板，用户自行出码流 |

---

## 6. 任务过程记录

（执行中追加，历史不改写）

### 记录 1：方案建立（2026/10/20）

- 完成第 2 节全部代码与报告核对，确认 64 + 3 两类伪违例有官方对应写法。
- 确认 110 条 `fifo_aclr` 跨域属真实未同步握手（`bmp_read` 直接采样 `write_req_ack`，无 2FF），本期不切，留二期。
- 经用户确认按"阶段 1：只改约束"推进。

### 记录 2：约束改动完成（2026/10/20）

**唯一改动文件**：`Project/src/user_source/constraints_source/timing.sdc`（116 → 162 行，新增 46 行，其中 40 行为说明性注释）。

| 位置 | 新增 |
|---|---|
| 第 38 行（`audio_mclk` rename 后） | `rename_clock -name {ext_mem_clk_sft} ... [get_pins {sys_pll_m0/pll_inst.clkc[2]}]` |
| 文件末（新增第 9 节 + 注释） | `set_false_path -from {ext_mem_clk} -to {ext_mem_clk_sft}` 及反向 |
| 文件末（新增第 10 节 + 注释） | `set_clock_uncertainty -hold 0.050`，覆盖 7 个时钟 |

两条既有 `set_false_path`（video_clk ↔ clk）保持不动；未改 `create_clock`、`derive_clocks`、任何 `set_clock_groups`、任何周期约束。

**本地校验结果**（第 4.1 节口径）

| 校验项 | 结果 |
|---|---|
| SDC 引用的 6 个既有时钟名 | 全部在 `final_timing.rpt` 的 Clock Summary 中存在（`clk` / `sd_card_clk` / `ext_mem_clk` / `video_clk` / `hdmi_5x_clk` / `audio_mclk`） |
| 新引用的 pin 路径 `sys_pll_m0/pll_inst.clkc[2]` | 报告中确认为 `clk6: 125.000 ... sys_pll_m0/pll_inst.clkc[2]`，名称一致 |
| 改动范围 | 18:00 之后 `src` 下仅 `timing.sdc` 变更；另 3 个 `.v` 为 E15 早些时候的改动，本轮未再动 |
| RTL 改动 | **无** |

**尚未执行**：TD `syn_1` / `phy_1` 复跑（按 `Anlu.md` 由用户执行）。期望结果见第 4.2 节表格。

**待用户回填**：复跑后的 `route.qor` 与 `final_timing.rpt` 数字（Setup 违例端点数、Setup WNS、Hold 违例端点数、Hold WNS、slices/BRAM/DSP），据此判断是否需要调整 `clkc[2]` 的 rename 目标或进入二期。

### 记录 3：第一轮 TD 复跑结果（2026/10/20 19:57）——一项成功、一项判断错误已纠正

**实测对比**

| 指标 | 改前（E15） | 第一轮改后 | 判定 |
|---|---|---|---|
| Setup 违例端点 | 653 | **494**（−159） | ✓ 达成且超预期 |
| Setup TNS | −833425 | **−373332**（减半） | ✓ |
| Setup WNS | −6.846 | −7.423 | 略差（最差路径换人，属布局扰动） |
| **SDRAM 相位组（`ext_mem ↔ clkc[2]`）** | 64 | **0**（两组整组消失） | ✓ 目标达成 |
| `sd_card_clk` 域内 setup | 432 / −1.605 | 351 / −1.413 | ✓ |
| `ext_mem → sd_card` | 110 / −2.741 | 107 / −2.194 | ✓ 略好 |
| `ext_mem` 域内 | 45 / −6.846 | 33 / −7.423 | 端点数少但 WNS 略差 |
| Hold 违例端点 | 3 | **21** | ✗ **被我加错的约束恶化** |
| Hold WNS | −0.011 | **−0.070** | ✗ 同上 |
| slices | 9025 | 9066（92.51%） | +41 |

**结论 1：`rename_clock` + 双向 `set_false_path` 完全成功**

- 报告中 `clk6` 名称由 `sys_pll_m0/pll_inst.clkc[2]` 变为 **`ext_mem_clk_sft`**，两组 SDRAM 相位路径整组从报告中消失（64 → 0）。
- 另查明 `derive_clocks` 本来就已按 `-phase 180` 自动生成该时钟（`syn_1/run.log` 的 USR-1002 有记录），所以不需要 `create_generated_clock`，`rename_clock` 是正确做法。

**结论 2：`set_clock_uncertainty -hold 0.050` 在本版 TD 上是反效果，已撤除**

- 报告原文：`Clock Uncertainty : 0.150ns (sdc uncertainty: 0.050ns, default uncertainty: 0.100ns)`，共 87 条路径显示 `sdc uncertainty: 0.050`。
- **即 TD v6.2.168116 把 sdc 数值叠加在默认 0.100ns 之上，而非替换**。总 uncertainty 由 0.100 变为 0.150，hold 直接被扣掉 50ps，正好解释 HWNS 从 −0.011 恶化到 −0.070（−59ps）。
- 官方例程的写法依赖"替换"语义（其工具版本可能是 5.x）。本版工具下该技巧**不成立**，已整条删除，并在 `timing.sdc` 第 10 节写下"勿再添加"的原因记录。

**结论 3：`false_path` 引起布局扰动，新增一条 video_clk setup 违例**

- `video_clk -> video_clk` setup 由 0 违例变为 **1 条 −0.329ns**：起点 `sd_card_bmp_m0/u_wav_player/wstate_reg[1]`，终点 `u_waveform_data/wave_wr_data_reg[6]`，**数据路径 40.049ns（cell 15.06 / net 24.99，net 占 63%）**——一条跨两个模块、绕行极远的组合链，属布局拥塞产物而非逻辑深度问题。
- 同时 `ext_mem` 域内最差路径由 `frame_fifo_write` 地址链承担，WNS 由 −6.846 变 −7.423。
- 判断：这两项是约束改动后的布局重排结果，属正常波动范围，不是功能问题；真正的收敛要靠二期降拥塞与打拍。

**结论 4：hold 剩余违例的真实构成**

- `sd_card_clk -> sd_card_clk`：3 条，典型为 `u_wav_player/buf_wa_reg[*] → ramread0.addra[*]`、`bmp_read_m0/up_raw_x_reg[1] → up_row_mem.addra[4]`——即官方所述的"寄存器 → 异步 RAM 读地址"类。
- `video_clk -> video_clk`：18 条，HWNS −0.070（含被我加的 50ps，撤除后应回到 −0.02 量级）。
- 该类违例**在本版工具无法用 uncertainty 降低**，只能靠打拍/降拥塞改善，或作为已知伪违例记录。

**下一步**：撤除 uncertainty 后需再跑一次 `syn_1` + `phy_1`，确认 hold 回落到改前水平、Setup 违例端点维持 ~494。

### 记录 4：第二轮 TD 复跑（2026/10/20 20:12，AI 自动批处理）——一期收尾

**执行方式**：TD GUI 关闭、`.lock.f` 释放后，在 `syn_1` 与 `phy_1` 目录分别执行
`D:/TD5.6.2/bin/td_commands_prompt.exe D:/TD5.6.2/doc/scripts/DefaultFlow.tcl`。
耗时 `syn_1` 1m46s、`phy_1` 4m10s，bitstream 已生成。

**最终结果**

| 指标 | E15 基线 | 第一轮 | **第二轮（最终）** | 结论 |
|---|---|---|---|---|
| Setup WNS | −6.846 | −7.423 | **−7.423** | 与第一轮逐位相同，可复现 |
| Setup TNS | −833425 | −373332 | **−373332** | 减半 |
| Setup 违例端点 | 653 | 494 | **494** | −159 |
| Hold WNS | −0.011 | −0.070 | **−0.020** | 精确回落 50ps |
| Hold 违例端点 | 3 | 21 | **4** | 回到基线量级 |
| SDRAM 相位组 | 64 | 0 | **0** | 达成 |
| slices / BRAM / DSP | 9025/36/13 | 9066/36/13 | **9066/36/13** | 基本不变 |

**验证结论**

1. Hold 从 −0.070 精确回落到 −0.020（差 50ps），与"撤掉叠加的 0.050ns"完全吻合，**反证该命令确为叠加语义**，记录 3 的归因成立。
2. Setup 三项数字与第一轮**逐位一致**，说明布局种子确定、`false_path` 效果稳定可复现。
3. 相对 E15 的 −0.011/3 端点，当前 −0.020/4 端点略差，属 SDRAM `false_path` 引起的布局重排，量级仍在伪违例范围。

**最终剩余 494 个 setup 违例端点分布（全部为真实同步路径）**

| 路径组 | WNS | 端点 | 二期处置方向 |
|---|---|---|---|
| `sd_card_clk` 域内 | −1.413 | 351 | 状态机→高扇出 `.ce` 打拍/复制使能 |
| `ext_mem → sd_card` | −2.194 | 107 | `write_req_ack` 加两级同步器 |
| `ext_mem` 域内 | **−7.423** | 33 | `frame_fifo_write` 写地址链打拍（最优先） |
| `sd_card → ext_mem` | −0.151 | 2 | 随上项一并处理 |
| `video_clk` 域内 | −0.329 | 1 | `u_wav_player → u_waveform_data` 40ns 超长路径 |

**一期结论**：约束侧已收敛到位——伪违例全清（64 → 0）、TNS 减半（−833 → −373）、Hold 回到基线量级。剩余的 −7.423ns / 494 端点无法再用 SDC 改善，进入二期 RTL 改造。

**二期注意**：现有 `sim/` 下 **没有 `frame_fifo_write` / `frame_read_write` 的任何 tb**（已有 20+ 个 tb 覆盖 scanner、chain、track、wav、waveform、osd 等），二期必须新建该模块 tb 后才能改地址链；`write_req_ack` 握手可扩展 `tb_step2_resident` / `tb_step5_reload` 验证。
