# Anlu 小步推进方案 时序收敛二期 D：frame_fifo_write 行跳转链打拍

> **来源**：二期 B 完成后（2026/10/20），`ext_mem_clk` 域内上升为第二差组 **−1.921ns / 61 个违例端点**，最差路径落在二期 A 刻意未动的**行跳转链**上。
> **当前稳定点**：E15 + 一期约束 + 二期 A/B（Setup 451 EP / WNS −2.203，Hold 1 EP / −0.004，slices 8995）｜**目标**：把行跳转换算寄存器化，消化该组违例。

---

## 1. 背景与目标

### 本次做

在 `SD/frame_fifo_write.v` 中，把**行跳转换算**（`write_line_jump_flip` / `write_line_jump_normal`）与**行尾比较值**（`write_active_last_x`）从组合逻辑改为**寄存器**，用寄存器化后的值参与逐像素地址推进。

### 本次不做

- 不动 `bmp_read` 深组合链（`sd_card_clk` 域内 390 端点 / −2.203），属二期 C。
- 不动二期 A 已完成的起始地址链、二期 B 已完成的 ack 同步。
- 不改端口、参数、状态机编码。

---

## 2. 当前代码事实

### 2.1 报告证据

`phy_1/final_timing.rpt`（二期 B 后）：

```
Path Group : ext_mem_clk -> ext_mem_clk
SWNS       : -1.921ns, STNS -53.157ns, 61 Viol Endpoints
最差路径   Begin : frame_fifo_write_m0/write_active_width_latch_reg[3]
          End   : frame_fifo_write_m0/App_wr_addr_r_reg[12].a[0]
          Data  : 9.641ns (cell 3.759 38%, net 5.882 62%)   ← 布线占 62%
          Logic : 7 级 ( LUT4=3  LUT5=2  ADDER=2 )
          Fanout: 45
```

### 2.2 RTL 中的位置

`SD/frame_fifo_write.v`（383 行）：

| 行 | 信号 | 运算 |
|---|---|---|
| 134 | `write_active_width_addr` | `width_latch` 零扩展 |
| 135 | `write_line_jump_flip` | `FRAME_WIDTH + width_addr - 1` → **1 加 + 1 减** |
| 136 | `write_line_jump_normal` | `FRAME_WIDTH - width_addr + 1` → **1 减 + 1 加** |
| 137 | `write_active_last_x` | `width_latch - 1` → **1 减** |
| 229 / 232 | 行尾判断与地址更新 | `if (wr_x == last_x) App_wr_addr_r <= App_wr_addr_r - jump_flip` |
| 242 / 245 | 同上（非 VFLIP） | `App_wr_addr_r <= App_wr_addr_r + jump_normal` |

即最差路径为：`width_latch` → 2 个加减器（jump） → 21 位加减器（地址） ，加上比较器参与的选择，共 **3 个加法器级联**，与报告 `ADDER=2 + LUT 若干` 吻合。

### 2.3 为什么可以安全地寄存器化

`write_active_width_latch` **只在 `S_ACK` 状态被写一次**（L219），此后整个 burst 期间保持不变。因此它的派生量（jump / last_x）在 `S_ACK` 之后一拍即可稳定，后续几十拍都有效。

时序余量核算：

| 事件 | 拍 |
|---|---|
| `S_ACK` 写入 `width_latch` | 第 T 拍 |
| 寄存器化后的 jump / last_x 有效 | 第 T+1 拍 |
| 最早可能用到 jump（`wr_x == last_x` 成立） | `S_CHECK_FIFO` → `S_WRITE_BURST`（置 `App_wr_en_r`）→ `App_wr_en` 有效，最少 T+3 拍 |

**最紧的情况是 `width = 1`**：`last_x = 0`，`wr_x` 复位值为 0，所以**第一个写使能拍**就命中行尾、立刻用 jump。此时距 T 已有 ≥3 拍，寄存器化的值早已稳定，安全。

这正是本次必须在 tb 里覆盖 `width = 1` 的原因（现有 tb 只有 `width = 3`）。

---

## 3. 改动步骤

### 步骤 1（先做）：扩展 `tb_frame_fifo_write.v` 覆盖 width=1

现有 tb 只有一组参数（`width=3, height=2`），行跳转在第 3 个像素后才发生。需增加第二组场景 `width=1, height=3`，让行跳转在**第一个像素后就发生**，专门压边缘时序。

新增期望序列（`FRAME_WIDTH=8`, `FRAME_HEIGHT=4`, `base=0`）：

| DUT | 推算 | 期望序列 |
|---|---|---|
| VFLIP=1 | `bottom_row = 0+3-1 = 2` → 起始 `2*8+0 = 16`；`jump = 8+1-1 = 8` | **16, 8, 0** |
| VFLIP=0 | 起始 `0*8+0 = 0`；`jump = 8-1+1 = 8` | **0, 8, 16** |

实现方式：tb 内引入 `phase` 标志与第二组历史数组，先跑场景 1（width=3）再跑场景 2（width=1），两次请求在同一对 DUT 上先后完成（模块支持 `S_END → S_IDLE` 复跑）。

**先对未改动 RTL 跑一遍，两个场景都必须 PASS**，这是后续改动的功能基线。

### 步骤 2：寄存器化 jump 与 last_x

在 `frame_fifo_write.v` 中：

1. 新增寄存器 `line_jump_q`（`ADDR_BITS` 位）与 `last_x_q`（16 位）。
2. 新增一个 `always` 块，`reset` 清零，否则每拍：
   - `last_x_q   <= write_active_last_x;`
   - `line_jump_q <= WRITE_V_FLIP ? write_line_jump_flip : write_line_jump_normal;`
3. 把 L229/L232/L242/L245 的比较与加减改为使用 `last_x_q` 与 `line_jump_q`：
   - `if (wr_x == last_x_q) ... App_wr_addr_r <= App_wr_addr_r - line_jump_q;`
   - `if (wr_x == last_x_q) ... App_wr_addr_r <= App_wr_addr_r + line_jump_q;`

改完后最差路径降为：`line_jump_q`（寄存器）→ 21 位加减器 → `App_wr_addr_r`，只剩 **1 个加法器**；比较器也变成 `wr_x` 与寄存器直连的 16 位比较。

### 步骤 3：本地回归

- `tb_frame_fifo_write` 两场景回归，要求与基线**逐项相同**。
- 全量 `vlog` 确认无新增错误。

### 步骤 4：TD 复跑

`syn_1` + `phy_1`，核对 `ext_mem_clk` 域内是否清零或大幅下降。
跑完把新 bitstream 同步到 `best_result`（按 `Anlu.md` 收尾规则）。

---

## 4. 验收方式

### 4.1 本地（我执行）

| 检查 | 判据 |
|---|---|
| `tb_frame_fifo_write` 改前基线（两场景） | PASS：`17,18,19,9,10,11` / `9,10,11,17,18,19`；`16,8,0` / `0,8,16` |
| 改后回归 | PASS 且逐项相同 |
| 全量 vlog | 无新增错误 |

### 4.2 TD（我执行）

| 指标 | 改前（二期 B 后） | 目标 |
|---|---|---|
| `ext_mem_clk → ext_mem_clk` 违例端点 | 61 | **显著减少或归零** |
| 该组 WNS | −1.921ns | **> 0** |
| 全局 Setup 违例端点 | 451 | **< 451** |
| 全局 Setup WNS | −2.203ns | 改善（新最差项应为 `sd_card_clk` 域内） |
| Hold | 1 EP / −0.004 | 不恶化 |
| slices | 8995（91.79%） | +约 37 个 FF，基本不变 |

### 4.3 上板（用户执行）

- 判据：PIC1~PIC4 装载显示正常、**无斜图/行错位**（行跳转直接影响行的落点）、切图/波形/音频无回归。
- 本次改动直接影响逐行地址推进，**必须上板看图像是否整幅正确**，不能只看 TD。

---

## 5. 回退点与风险

### 回退点

- 改前稳定版：**二期 B 完成态**（已上板通过；Setup 451 EP / −2.203，slices 8995）。仅改 `frame_fifo_write.v`，撤销即回。

### 风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| `width=1` 时 jump 寄存器尚未稳定就被使用 | 行跳转错 → 图像整行错位 | §2.3 推算至少余 3 拍；tb 专门加 width=1 场景 |
| 寄存器化后与组合值在 `S_ACK` 当拍不一致 | 首行落点错 | `S_ACK` 期间不使用 jump，首次使用在 burst 阶段 |
| 新增 37 个 FF 引起布局重排 | 其他组数字波动 | 与 A/B 同现象，属拥塞期常态；若显著恶化则回退 |
| 布线占 62%（net 5.882ns）说明拥塞 | 单靠打拍未必清零 | 打拍可先把逻辑级数降到 1；若仍不满足，说明是布线拥塞，转入全局降拥塞（C） |

---

## 6. 任务过程记录

（执行中追加，历史不改写）

### 记录 1：方案建立（2026/10/20）

- 完成报告与 RTL 核对：最差路径 `width_latch → jump(2 加减) → 地址(1 加减)`，与 `ADDER=2 + LUT` 吻合。
- 确认 `width_latch` 仅在 `S_ACK` 写一次，其后整个 burst 恒定，寄存器化安全。
- 识别 `width=1` 为最紧边缘场景，现有 tb 未覆盖，需先扩展 tb。

### 记录 2：TB 扩展与 RTL 改动完成（2026/10/20）

**步骤 1：扩展 `tb_frame_fifo_write.v` 为双场景**

- 由单场景改为 `phase` 控制的两场景：先跑 `width=3`（原 A 基线），再跑 `width=1`（D 边缘），同一对 DUT 连续两次请求。
- 新增第二组历史数组与计数器，判定同时覆盖两组期望序列。
- **改前基线（未动 RTL）PASS**，四个序列与手算一致：

| 场景 | DUT | 实测 |
|---|---|---|
| S1 width=3 | VFLIP=1 | 17,18,19,9,10,11 |
| S1 width=3 | VFLIP=0 | 9,10,11,17,18,19 |
| **S2 width=1** | VFLIP=1 | **16,8,0** |
| **S2 width=1** | VFLIP=0 | **0,8,16** |

**步骤 2：RTL 寄存器化**

`SD/frame_fifo_write.v` 改动：

| 内容 | 说明 |
|---|---|
| 新增 `reg write_last_x_q`（L95）、`reg write_line_jump_q`（L96） | 行尾比较值与行跳转换算的寄存版本 |
| 复用 A 步建立的流水 `always` 块（L189~197） | `reset` 清零；否则每拍 `last_x_q <= write_active_last_x`、`line_jump_q <= WRITE_V_FLIP ? jump_flip : jump_normal` |
| L235 / L248 | `if(wr_x == write_active_last_x)` → `if(wr_x == write_last_x_q)` |
| L238 | `App_wr_addr_r - write_line_jump_flip` → `- write_line_jump_q` |
| L251 | `App_wr_addr_r + write_line_jump_normal` → `+ write_line_jump_q` |

组合式 `write_line_jump_flip/normal`、`write_active_last_x` 三条 wire 保留作为寄存器的输入（不再直接驱动地址加法器）。因 `WRITE_V_FLIP` 是参数常量，综合后只会保留一个分支的加法器。

**步骤 3：本地回归**

| 检查 | 结果 |
|---|---|
| `tb_frame_fifo_write` 两场景 | **PASS**，四个序列与基线**逐项相同** |
| 全量 `vlog`（65 模块） | 仅 2 条既有厂商加密文件错误，无新增 |

**步骤 4**：TD `syn_1` + `phy_1` 已提交（GUI 保持开启），结果待记录 3 回填。

### 记录 3：TD 复跑结果（2026/10/20 21:18）——目标达成

**过程插曲**：`syn_1` 正常完成（1m27s，`gate.qor` 20:59），但 `phy_1` 首次运行在 global routing 阶段**被中断**（后台任务服务变为 inactive，父进程结束时连带杀掉了 TD 子进程；日志停在 `Global iterations in 20 thread ...`，无错误码）。因 `syn_1` 已用当前 RTL 完成，只单独重跑 `phy_1`（6m41s）即得到完整结果。**教训：TD 这类 2~7 分钟的流程应用前台调用 + 有限超时，不要挂在后台任务上。**

**逐组对比**

| 路径组 | B 后 | **D 后** | 结果 |
|---|---|---|---|
| `ext_mem_clk` 域内（本次目标） | −1.921 / 61 | **−0.361 / 14** | **达成**，接近清零 |
| `sd_card_clk` 域内 | −2.203 / 390 | **−1.277 / 410** | WNS 改善，但成为唯一大头 |
| `ext_mem → sd_card` | +0.076 / 0 | +0.165 / 0 | 保持干净 |
| `sd_card → ext_mem` | +0.171 / 0 | +0.229 / 0 | 干净 |
| `video_clk` 域内 | 0 | −0.011 / 2 | 出现 2 条伪违例 |
| Hold 全局 | −0.004 / 1 | −0.011 / 2 | 略差（伪违例量级） |

**全局**

| 指标 | B 后 | D 后 | 变化 |
|---|---|---|---|
| Setup WNS | −2.203 | **−1.277** | +0.926 |
| Setup TNS | −364268 | **−208424** | 明显改善 |
| Setup 违例端点 | 451 | **424** | −27 |
| slices | 8995（91.79%） | 9009（91.93%） | +14 |
| wire length | 1829656 | 1758136 | −71520 |

**结论**

1. **D 目标达成**：`ext_mem_clk` 域内从 −1.921/61 收到 −0.361/14，行跳转链不再是瓶颈。
2. **全局明显改善**：WNS +0.93ns、TNS 降 43%、线长减少 7.2 万，寄存器化顺带缓解了拥塞。
3. **剩余问题高度集中**：424 个端点中 **410 个（97%）在 `sd_card_clk` 域内**，是唯一的大头，对应二期 C。
4. 新最差路径：`bmp_read_m0/mult4` → `up_row_read_byte_cnt_reg[11].ce`，数据 11.206ns、逻辑 6 级（LUT4x3 + ADDERx2 + LUT5x1）、扇出 10——仍是 `bmp_read` 内部乘法/计数链。
5. Hold 的 2 条 −0.011ns 属已知伪违例量级，不影响功能，留待 C 完成后复观察。

**二期累计（从 E15 起点算）**：Setup 违例端点 **653 → 424**（−229），Setup WNS **−6.846 → −1.277**（改善 5.4 倍）；Hold 在 A 步曾一度全清（+0.011/0），当前为 −0.011/2。
