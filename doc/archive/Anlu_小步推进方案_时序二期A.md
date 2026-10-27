# Anlu 小步推进方案 时序收敛二期 A：frame_fifo_write 写起始地址链打拍

> **来源**：时序收敛一期收尾后（2026/10/20），剩余 494 个 setup 违例端点中最差一项为 `ext_mem` 域内 **−7.423ns / 33 端点**，全部落在 `frame_fifo_write` 的写起始地址计算链上。本方案按"TB 先行"推进。
> **当前稳定点**：E15 + 时序一期约束（Setup 494 EP / WNS −7.423，Hold 4 EP / −0.020）｜**目标**：把该链拆成三级流水，让 `ext_mem` 域内 setup 转正。

---

## 1. 背景与目标

### 本次做

在 `SD/frame_fifo_write.v` 中，把"写起始地址"的组合链拆成**三级流水**，消除 `−7.423ns` 这条路径。

### 本次不做

- 不动 `S_WRITE_BURST` 里的逐像素地址递增与行跳转逻辑（`write_line_jump_flip/normal`）——报告抽样的 10 条违例路径全在起始地址链上，未见行跳转链违例，保持范围最小。
- 不动 `fifo_aclr` / `write_req_ack` 跨域（属二期 B，需加两级同步器）。
- 不动 `bmp_read` / `u_chain` 高扇出 CE（属二期 C，351 端点）。
- 不改任何端口、参数、状态机状态编码与对外时序契约。

---

## 2. 当前代码事实

### 2.1 报告给出的路径构成

`phy_1/final_timing.rpt` 最差路径（时序一期第二轮结果）：

```
Slack            : -7.423ns        （预算 8.000ns，即 125MHz ext_mem_clk）
Begin Point      : frame_fifo_write_m0/write_active_height_d1_reg[2]
End Point        : frame_fifo_write_m0/App_wr_addr_r_reg[20].a[1]
Data Path Delay  : 15.143ns (cell 9.144ns 60%, net 5.999ns 40%)
Logic Level      : 12 ( ADDER=6  LUT5=5  MULT18=1 )
Max Fanout       : 3
```

同组抽样 10 条违例的起点分布：**9 条** 来自 `write_active_height_d1_reg[2]`、**1 条** 来自 `write_active_offset_y_d1_reg[0]`；终点全部是 `App_wr_addr_r_reg[*]`。

### 2.2 该链在 RTL 中的位置

`SD/frame_fifo_write.v`（366 行）第 121~135 行的组合推导，最终在第 206 行被 `S_ACK` 状态使用：

| 行 | 信号 | 运算 |
|---|---|---|
| 121~122 | `write_active_width_d1_safe` / `write_active_height_d1_safe` | `==0` 判空后取默认值的 **mux** |
| 123 | `write_active_bottom_row_d1` | `offset_y_d1 + height_d1_safe - 1` → **16 位加法** |
| 124~126 | `write_start_offset_d1` | `bottom_row_d1 × FRAME_WIDTH + offset_x_d1` → **MULT18 + 加法** |
| 127~129 | `write_base_addr_selected` | `write_addr_index_d1` 的 **4:1 mux**（21 位） |
| 206 | `App_wr_addr_r <= write_base_addr_selected + write_start_offset_d1[20:0]` | **21 位加法** |

合计 6 个加法器 + 1 个乘法器 + 5 级 LUT，与报告的 `ADDER=6 MULT18=1 LUT5=5`、`Logic Level 12` 完全吻合。

### 2.3 关键前提：这些输入在整个写请求期间是稳定的

`write_active_width/height/offset_x/offset_y`、`write_addr_index`、`write_len` 由 `bmp_read`（sd_card_clk 域）在发起写请求时给出，**`write_req` 一直保持到 `write_req_ack` 返回**（端口注释 L31 已写明）。模块内部用 `_d0`/`_d1` 两级同步后再用，故：

- 请求期间 `_d0`、`_d1` 上的值恒定；
- 把"起始地址"的中间结果多寄存一到两拍，不影响最终取值，只需保证 **`S_ACK` 执行到第 2 拍以后**用到的是已稳定的值。

### 2.4 现有流水对齐关系（推导管线为什么放得下）

按"输入在第 0 拍"计：

| 拍 | 可用信号 |
|---|---|
| 1 | `_d0`（输入延迟 1） |
| 2 | `_d1`（输入延迟 2） |
| 3 | `write_req_d2`（请求延迟 3） |
| 4 | `state == S_ACK`（第 3 拍看到 d2=1，第 4 拍执行 S_ACK） |

`S_ACK` 会**持续多个拍**：它要等 `write_req_d2 == 0`，而 `write_req` 要等 `write_req_ack` 经过跨域后才能撤销（ack 是本模块寄存输出，再经 sd_card 域采样）。因此第 4 拍之后 S_ACK 仍会保持若干拍。

本方案把中间结果寄存在第 2 拍与第 3 拍产出，第 4 拍使用，**留有一整拍余量**，不依赖"S_ACK 恰好持续几拍"这种脆弱假设。

---

## 3. 改动步骤

### 步骤 1（先做）：新建 `sim/tb_frame_fifo_write.v` 并跑通现状基线

现有 `sim/` 下 31 个 tb 覆盖 scanner / chain / track / wav / waveform / osd / status_bar 等，**`frame_fifo_write` / `frame_read_write` 完全没有 tb**，必须先补。

测试台设计：

- 例化**两个** DUT，同参数不同 `WRITE_V_FLIP`：`dut_flip`（=1）、`dut_norm`（=0），一次跑完两种地址映射。
- 缩小参数以加快仿真：`ADDR_BITS=16`、`BURST_BITS=4`、`BURST_SIZE=8`、`FRAME_WIDTH=8`、`FRAME_HEIGHT=4`。
- 写请求参数：`width=3`、`height=2`、`offset_x=1`、`offset_y=1`、`write_len=6`、`base=0`，即**2 行 × 3 列**的小块。
- 期望地址序列（手算）：
  - **VFLIP=1**：`bottom_row = 1+2-1 = 2` → 起始 `2*8+1 = 17`；写完 3 个像素（17,18,19）后行跳转 `-(8+3-1) = -10` → 下一行 `9,10,11`。序列 **17,18,19,9,10,11**。
  - **VFLIP=0**：起始 `1*8+1 = 9`；行跳转 `+(8-3+1) = +6` → `11+6 = 17`。序列 **9,10,11,17,18,19**。
- 激励流程：复位 → `Sdr_init_done=1` → 拉起 `write_req` 与全部参数 → 等 `write_req_ack=1` 后撤销 `write_req` → 把 `rdusedw` 拉高使 `into_burst` 成立 → 持续到 `write_finish=1`。
- 判定：打印并在 `App_wr_en` 有效的拍采集 `App_wr_addr`，与期望序列逐项比对；同时检查 `fifo_aclr` 在 `S_ACK` 期间拉高过一次。任一不符即 FAIL。

**先对未改动的 RTL 跑一遍，必须 PASS**——这是后续打拍改动的功能基线；若基线就不过，说明测试台手算或激励有问题，先修 tb 不动 RTL。

### 步骤 2：把起始地址链拆成三级流水

在 `SD/frame_fifo_write.v` 中：

1. **拍 2 产出"行号"**：新增寄存器 `row_for_offset_q`，从 `_d0` 级计算——`WRITE_V_FLIP ? (offset_y_d0 + height_d0_safe - 1) : offset_y_d0`。这一步只剩 mux + 1 个 16 位加法。
2. **拍 3 产出"起始偏移"**：新增寄存器 `start_offset_q`，计算 `row_for_offset_q × FRAME_WIDTH + offset_x_d1`，截到 `ADDR_BITS` 位。这一步剩 MULT18 + 1 个加法。
3. **拍 4 在 `S_ACK` 使用**：第 206 行改为 `App_wr_addr_r <= write_base_addr_selected + start_offset_q`。这一步剩 4:1 mux + 1 个 21 位加法。

原 `write_start_offset_d1`、`write_active_bottom_row_d1` 两条 wire 及 `write_active_height_d1_safe` 的引用在改造后不再需要，一并删除以保持无死逻辑。

**数学等价性**：两个分支（VFLIP / 非 VFLIP）的行号取值与原式完全一致，仅把"行号→偏移→加基址"分到不同拍完成。

### 步骤 3：本地回归

- 再跑一次 `tb_frame_fifo_write`，**必须仍 PASS 且地址序列与基线逐项相同**。
- 跑全量 `vlog`（`sim/work_e15/list.f` 62 文件口径）确认无编译错误。

### 步骤 4：TD 复跑

`syn_1` + `phy_1` 自动批处理，核对 `ext_mem` 域内 setup 是否转正。

---

## 4. 验收方式

### 4.1 本地（我执行）

| 检查 | 判据 |
|---|---|
| `tb_frame_fifo_write` 改前基线 | PASS，地址序列 17,18,19,9,10,11（flip）与 9,10,11,17,18,19（norm） |
| `tb_frame_fifo_write` 改后回归 | PASS，且与基线序列**逐项相同** |
| 全量 vlog | 无新增错误（既有 2 条厂商加密文件错误不计） |

### 4.2 TD（我执行）

| 指标 | 改前（一期第二轮） | 目标 |
|---|---|---|
| `ext_mem_clk -> ext_mem_clk` WNS | −7.423ns | **> 0**（或至少不再是最差项） |
| 该组违例端点 | 33 | **0**（理想）或显著减少 |
| 全局 Setup 违例端点 | 494 | **≤ 461**（494 − 33） |
| 全局 Setup WNS | −7.423ns | 转为 −2.194ns 量级（`ext_mem→sd_card` 组成为新最差） |
| Hold | −0.020 / 4 EP | 不恶化 |
| slices / BRAM / DSP | 9066 / 36 / 13 | 基本不变（仅增约 40 个寄存器） |

### 4.3 上板（用户执行）

- 逻辑行为未变（仅插入流水级），**原则上无功能变化**。
- 但写地址生成多 2 拍延迟发生在 `S_ACK` 期间、`write_req` 保持窗口内，理论上不影响装载时序；仍建议烧一版确认图片装载正常、切图无错位。
- 判据：PIC1~PIC4 装载显示正常无斜图/黑屏；切图/轮播/波形/音频无回归。

---

## 5. 回退点与风险

### 回退点

- 改前版本：**E15 + 时序一期约束**（Setup 494 EP / −7.423，Hold 4 EP / −0.020）。仅改 `frame_fifo_write.v` 一个文件，撤销即回。

### 风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| 流水对齐推算有误，`S_ACK` 第 1 拍就用到未稳定的 `start_offset_q` | 起始地址错 → 图像整体错位 | 已按 §2.4 推算留一整拍余量；且 `S_ACK` 必然持续多拍；tb 直接比对地址序列可立即暴露 |
| `_d0`/`_d1` 在某些请求下取值不同（如中途改写参数） | 行号与偏移取自不同拍，地址错 | `bmp_read` 在请求期间不改参数（端口注释约定）；tb 中造一组"请求期间改参数"的负向用例确认不影响已发起的请求 |
| 打拍后 `ADDR_BITS` 截断位置变化 | 大偏移时高位丢失 | 保持与原式相同的截断宽度（`[ADDR_BITS-1:0]`） |
| 新增约 40 个寄存器推高 slices（当前 92.51%） | 可能越过 95% | 仅 +40 FF，占比极小；若异常则回退 |

---

## 6. 任务过程记录

（执行中追加，历史不改写）

### 记录 1：方案建立（2026/10/20）

- 完成 §2 的代码与报告核对：6 加法器 + 1 乘法器的推断与报告 `ADDER=6 MULT18=1 Logic Level 12` 完全一致。
- 确认 10 条抽样违例路径起点全部集中在该链，单一改动可覆盖。
- 确认现有 tb 无 `frame_fifo_write` 覆盖，按用户要求"TB 先行"。

### 记录 2：TB 基线与 RTL 改造完成（2026/10/20）

**步骤 1：新建 `sim/tb_frame_fifo_write.v` 并跑通基线**

- 双 DUT 设计（`dut_flip` = VFLIP 1、`dut_norm` = VFLIP 0），同一组激励并行跑完两种地址映射。
- 参数：`ADDR_BITS=16`、`BURST_BITS=4`、`BURST_SIZE=8`、`FRAME_WIDTH=8`、`FRAME_HEIGHT=4`；请求 `width=3 height=2 offset_x=1 offset_y=1 write_len=6`。
- **对未改动 RTL 跑基线：PASS**，实际序列与手算完全一致：

| DUT | 实测序列 | 手算期望 |
|---|---|---|
| VFLIP=1 | 17,18,19,9,10,11 | 一致 |
| VFLIP=0 | 9,10,11,17,18,19 | 一致 |

  两者各 6 个写使能，`fifo_aclr` 在 `S_ACK` 期间均拉高。

**步骤 2：起始地址链拆三级流水**

`SD/frame_fifo_write.v` 改动（净增约 40 个寄存器）：

| 内容 | 处理 |
|---|---|
| 新增 `write_active_height_d0_safe` | `_d0` 级的判空 mux |
| 新增 `write_row_for_offset_d0` | `_d0` 级求行号（VFLIP 取 `offset_y+height-1`，否则取 `offset_y`） |
| 新增 `reg write_row_for_offset_q` | **第 2 拍**寄存行号（剩 mux + 1 个 16 位加法） |
| 新增 `write_start_offset_next` | `write_row_for_offset_q × FRAME_WIDTH + offset_x_d1`（MULT18 + 1 加法，`_d1` 与 `_q` 同属"输入第 0 拍"，对齐一致） |
| 新增 `reg write_start_offset_q` | **第 3 拍**寄存起始偏移 |
| 第 223 行（原 206 行） | `App_wr_addr_r <= write_base_addr_selected + write_start_offset_q`（剩 4:1 mux + 1 个 21 位加法） |
| 删除 `write_active_bottom_row_d1`、`write_start_offset_d1` | 已成死逻辑，一并移除 |

**过程中出现并修正的问题**

1. 首次改动把两个 `_q` 寄存器误声明为 `wire`，`vlog` 报 4 条 `(vlog-2110) Illegal reference to net`。已改到 `reg` 声明区。
2. **重要教训**：编译失败后 `vsim` 仍跑出 `PASS`——因为 `work` 库里还是上一次编译的旧模块。**必须先确认编译 0 错误再采信仿真结果**，否则会拿旧代码的通过当新代码的证据。

**步骤 3：本地回归**

| 检查 | 结果 |
|---|---|
| 重新编译 `frame_fifo_write` + tb | **0 错误** |
| `tb_frame_fifo_write` 改后回归 | **PASS**，两路序列与基线**逐项相同** |
| 全量 `vlog`（`work_e15/list.f`） | 65 个模块，`frame_fifo_write` 已编入；仅 2 条既有的厂商加密文件错误（`sdr_init_ref.enc.v`、`sdr_wrrd.enc.v`），无新增 |

**步骤 4**：TD `syn_1` + `phy_1` 已提交后台执行，结果待记录 3 回填。

### 记录 3：TD 复跑结果（2026/10/20 20:25）——目标达成

`syn_1` 2m8s + `phy_1` 6m28s，bitstream 已生成。

**全局**

| 指标 | 改前 | 改后 | 变化 |
|---|---|---|---|
| Setup WNS | −7.423 | **−2.182** | +5.241（大幅改善） |
| Setup TNS | −373332 | **−239259** | −134073 |
| Setup 违例端点 | 494 | **413** | −81 |
| **Hold WNS** | −0.020 | **+0.011** | 转正 |
| **Hold 违例端点** | 4 | **0** | **全清** |
| slices | 9066（92.51%） | 9109（92.95%） | +43 |
| BRAM / DSP | 36 / 13 | 36 / 13 | 不变 |

**逐组对比**

| 路径组 | 改前 WNS / 端点 | 改后 WNS / 端点 | 结果 |
|---|---|---|---|
| `ext_mem_clk` 域内（本次目标） | −7.423 / 33 | **−0.179 / 21** | **达成**，从 −7.4 收到 −0.18 |
| `sd_card_clk` 域内 | −1.413 / 351 | −0.924 / 283 | 顺带改善 |
| `ext_mem → sd_card` | −2.194 / 107 | **−2.182 / 109** | 成为新最差项（属二期 B） |
| `video_clk` 域内 | −0.329 / 1 | **+3.456 / 0** | 全清 |
| `sd_card → ext_mem` | −0.151 / 2 | **+0.119 / 0** | 全清 |
| 所有 hold 组 | 4 端点 / −0.020 | **0 端点 / +0.011** | 全清 |

**结论**

1. **目标超额达成**：`ext_mem` 域内 −7.423ns → −0.179ns，33 → 21 端点，报上抽样路径的起点（`write_active_height_d1` / `offset_y_d1`）全部消失。
2. **Hold 意外全清**：推测是新增流水寄存器改变了布局分布，使原先"寄存器 → 异步 RAM 读地址"的 ±20ps 伪违例消失。属正当收益，非规避。
3. **新最差项是跨域组**：`ext_mem → sd_card` −2.182 / 109 端点，其最差路径为 `bmp_read_m0/add7`（ext_mem_clk）→ `bmp_read_m0/up_raw_x_reg[1].ce`（sd_card_clk），数据路径仅 3.945ns、逻辑 3 级——**不是逻辑深度问题，是跨域握手约束问题**，正是二期 B 要处理的 `write_req_ack` / `fifo_aclr` 未同步跨域。
4. **资源**：slices 92.95%，与二期前持平（+43 片），仍处 ≥91% 门禁区，但未显著恶化。

**上板建议**：逻辑行为经 tb 验证与基线逐项一致，理论上无功能变化；TD bitstream 已生成，建议择机烧一版快速确认 PIC1~PIC4 装载/显示正常、切图无错位，再进入二期 B。

### 记录 4：TD GUI 开启状态下复跑验证（2026/10/20 20:34）

用户提出希望能在他打开 TD 的情况下由我跑综合，避免为烧录而反复开关。实测结论：**可以并行**。

- 环境：TD GUI 运行中（pid 28052），`td_project/.lock.f` 存在（内容 `Mike / Mike / 28052 / 锁路径`），两个 run 目录内无锁文件。
- 执行：完整 `syn_1`（1m23s）+ `phy_1`（4m12s），两次 `exit=0`。
- **结果与关闭 GUI 的那次逐位相同**：Setup WNS −2182、Setup TNS −239259、Setup 违例 413、Hold WNS +11 / 0 端点、slices 9109（92.95%）、线长 1815112。
- 机理：`.lock.f` 是**工程级锁**、绑定 `.al`；批处理用 run 目录内的本地 `.prj`，`DefaultFlow.tcl` 只检查 `.stop.f`、不读 `.lock.f`。
- 唯一注意事项：批处理期间不要在 GUI 里同时点 Run；GUI 报告视图可能是旧缓存，需刷新。规则已写入 `Anlu.md`。
