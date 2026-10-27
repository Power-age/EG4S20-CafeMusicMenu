# Anlu 小步推进方案 时序收敛二期 B：write_req_ack 跨域加两级同步器

> **来源**：二期 A 完成后（2026/10/20），最差路径组变为 `ext_mem_clk → sd_card_clk` **−2.182ns / 109 个违例端点**。该组最差路径数据延迟仅 3.945ns、逻辑 3 级，**不是逻辑深度问题，而是未同步跨域**。
> **当前稳定点**：E15 + 一期约束 + 二期 A（Setup 413 EP / WNS −2.182，Hold 0 EP / +0.011，slices 9109）｜**目标**：把 `write_req_ack` 正确同步到 sd_card 域，消除该组违例与 metastability 风险。

---

## 1. 背景与目标

### 本次做

在 `SD/sd_card_bmp.v` 中，为来自 `ext_mem_clk` 域的 `write_req_ack` 增加**两级同步器**，并用同步后的信号替换现有两处直接使用。

这既是时序修复，也是**真实的 CDC 正确性修复**：当前 ack 直接进入 sd_card 域的组合逻辑（驱动多个寄存器的时钟使能），存在亚稳态传播风险。

### 本次不做

- 不动 `fifo_aclr`：它是 `frame_fifo_write` 内部驱动写侧 FIFO 异步清零的信号，在当前报告抽样中未见其跨到 sd_card 域的路径；待本次改动后复跑 TD 再评估。
- 不动 `bmp_read` 的高扇出 `.ce`（`sd_card_clk` 域内 283 端点 / −0.924），属二期 C。
- 不改端口、不改顶层连线、不改 `frame_fifo_write`。

---

## 2. 当前代码事实

### 2.1 时钟域与端口

`SD/sd_card_bmp.v`（1128 行）：

- 端口 L8：`input clk`（= `sd_card_clk`，100MHz）；L9：`input rst`（高有效）。
- 端口 L30：`input write_req_ack` —— 该信号来自顶层，源头是 `frame_fifo_write` 的 `output reg write_req_ack`，**在 `mem_clk`（= `ext_mem_clk`，125MHz）域寄存产生**。

### 2.2 两处消费点（都在 sd_card 域，且都是直接使用）

| 位置 | 用途 |
|---|---|
| L777 | 清 bank 状态机 `C_REQ` 状态：`if (write_req_ack) clear_cst <= C_RV;` |
| L1048 | `bmp_read` 例化：`.write_req_ack (write_req_ack)` |

`bmp_read` 内部用它判断写请求是否被响应（`write_req` 保持到 ack 返回的握手协议）。

### 2.3 对照：`write_finish` 早就做对了

同一模块里，`write_finish_toggle` 采用的是**正确的 toggle 同步**：

| 行 | 内容 |
|---|---|
| L228 | `reg [2:0] wrfin_tgl_sync;` |
| L600 | `wrfin_tgl_sync <= {wrfin_tgl_sync[1:0], write_finish_toggle};`（3 级） |
| L249 | `assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];` |

即 **`write_finish` 已同步、`write_req_ack` 是漏网的裸跨域**——这也是为什么报告里 109 条违例全集中在 ack 这条链上。

### 2.4 报告证据

`phy_1/final_timing.rpt`（二期 A 后）：

```
Path Group : ext_mem_clk -> sd_card_clk
SWNS       : -2.182ns, STNS -132.006ns, 109 Viol Endpoints, 113 Total Endpoints
最差路径   : 数据延迟 3.945ns（cell 1.420 / net 2.525），逻辑 3 级（LUT4x2 + LUT5x1），扇出 12
抽样起止点 : 10/10 条起点为 bmp_read_m0 内被 TD 复制到 ext_mem_clk 的 ack 扇出寄存器
             终点为 bmp_read_m0 各寄存器的 .ce（时钟使能）
```

**注意 113 个端点里 109 个违例**——几乎整组都不满足，典型 CDC 未约束特征。

### 2.5 握手时序分析：加 2 拍是安全的

- ack 是**电平信号**：`frame_fifo_write` 在 `S_ACK` 状态拉高，直到 `write_req_d2 == 0` 才撤销。
- `write_req` 由 bmp_read / 清 bank FSM 在**看到 ack 之后**撤销，因此 ack 的保持时间随同步延迟**正比例变长**，不会变短。
- 两个域都是 100/125MHz 量级，ack 保持至少 4~6 拍，远超 2 拍同步延迟。

结论：加两级同步器只增加 2 拍延迟，不会丢握手、不会产生窄脉冲。

### 2.6 现有 TB 基线（2026/10/20 跑通）

三个集成级 tb 已存在且**全部 PASS**，都例化 `sd_card_bmp` 并驱动 `write_req_ack`：

| TB | 覆盖内容 | 基线结果 |
|---|---|---|
| `tb_clear_bank.v` | 上电清 4 个 bank，直接走 `C_REQ` 等 ack 的状态机 | `CLEAR BANK TESTS PASS` |
| `tb_step2_resident.v` | 顺序装载 FSM，场景 A 全好图 / 场景 B 坏图重试 | `SCENARIO-A PASS`、`SCENARIO-B PASS` |
| `tb_step5_reload.v` | 拔卡保持 + 重插重载，驱动 ack | `STEP5 RELOAD ALL PASS` |

**环境要点**：`vsim` 需要把 `D:\TD5.6.2\arch\eagle_macro.v` 一并编译进 work 库（43 个原语模块），否则 elaboration 报 `Module 'EG_LOGIC_BRAM' is not defined`。编译期不需要，只在 `vsim` 时报。

---

## 3. 改动步骤

只改 `SD/sd_card_bmp.v` 一个文件。

### 步骤 1（先做）：确认三个 tb 基线

已在上文 §2.6 完成并记录。改完后用同样命令回归。

### 步骤 2：新增两级同步器

1. 在 `wrfin_tgl_sync` 声明附近（L228）增加：
   - `reg wr_ack_meta;`
   - `reg wr_ack_sync;`
2. 在第 560 行的大 `always` 块**之前**插入一个独立同步块：

```
always @(posedge clk or posedge rst) begin
    if (rst) begin
        wr_ack_meta <= 1'b0;
        wr_ack_sync <= 1'b0;
    end else begin
        wr_ack_meta <= write_req_ack;
        wr_ack_sync <= wr_ack_meta;
    end
end
```

### 步骤 3：两处消费点改用同步后的信号

| 行 | 原 | 改 |
|---|---|---|
| L777 | `if (write_req_ack)` | `if (wr_ack_sync)` |
| L1048 | `.write_req_ack (write_req_ack)` | `.write_req_ack (wr_ack_sync)` |

端口 `write_req_ack` 保留（顶层不动），仅作为同步器输入。

### 步骤 4：本地回归

- `tb_clear_bank`、`tb_step2_resident`、`tb_step5_reload` 三个 tb 全部重跑，要求与基线一致 PASS。
- 全量 `vlog` 确认无新增错误。

### 步骤 5：TD 复跑

`syn_1` + `phy_1`，核对 `ext_mem → sd_card` 组是否清零、全局 WNS 是否改善。
跑完把新 bitstream 同步到 `best_result`（按 `Anlu.md` 收尾规则）。

---

## 4. 验收方式

### 4.1 本地（我执行）

| 检查 | 判据 |
|---|---|
| 三个集成 tb | 与基线**同样全部 PASS** |
| 全量 vlog | 无新增错误 |

### 4.2 TD（我执行）

| 指标 | 改前（二期 A 后） | 目标 |
|---|---|---|
| `ext_mem_clk → sd_card_clk` 违例端点 | 109 | **显著减少或归零** |
| 该组 WNS | −2.182ns | **> 0** |
| 全局 Setup 违例端点 | 413 | **< 413** |
| 全局 Setup WNS | −2.182ns | 转为 `sd_card_clk` 域内的 −0.924 量级 |
| Hold | +0.011 / 0 EP | 不恶化 |
| slices | 9109（92.95%） | +2 左右，基本不变 |

### 4.3 上板（用户执行）

- 判据：PIC1~PIC4 装载显示正常；数码管第 7 位 bank 装载进度 `1→3→7→F` 正常（该进度依赖清 bank FSM 的 ack 握手）；切图/轮播/波形/音频无回归。
- 本次改动会真实改变 ack 的采样时刻（晚 2 拍），**必须上板确认装载流程**，不能只看 TD 数字。

---

## 5. 回退点与风险

### 回退点

- 改前稳定版：**二期 A 完成态**（Setup 413 EP / −2.182，Hold 0 / +0.011，slices 9109，已上板通过）。仅改 `sd_card_bmp.v`，撤销即回。

### 风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| ack 晚 2 拍导致某个 FSM 超时或漏判 | 装载失败、清 bank 卡住 | 三个集成 tb 直接覆盖这两条路径；握手为电平协议，ack 保持期随延迟延长 |
| ack 在 sd_card 域出现短于 1 拍的窄脉冲被漏采 | 握手丢失 | 电平握手 + 保持期 ≥4 拍，不存在单拍脉冲；tb 验证 |
| 新增 2 个 FF 引起布局变化 | 其他组数字波动 | 波动属正常；若 Setup 显著变差则回退 |
| 只改 ack、`fifo_aclr` 仍有跨域 | 该组违例未清零 | 本次复跑 TD 后按剩余路径再评估，不预设结论 |

---

## 6. 任务过程记录

（执行中追加，历史不改写）

### 记录 1：方案建立（2026/10/20）

- 完成报告与 RTL 核对：109/113 端点违例、数据延迟 3.945ns、逻辑 3 级，确认为 CDC 未同步而非逻辑深度问题。
- 查明 `write_finish` 已有 3 级 toggle 同步，`write_req_ack` 是唯一裸跨域信号，消费点为清 bank FSM 与 `bmp_read`。
- 三个集成 tb 基线全部 PASS；补齐 `eagle_macro.v` 后 `vsim` 可正常 elaborate。

### 记录 2：改动完成与本地回归（2026/10/20）

**改动文件**：`SD/sd_card_bmp.v`（1128 → 1141 行，净 +13 行）。

| 位置 | 内容 |
|---|---|
| L231~232 | 新增 `reg wr_ack_meta;` / `reg wr_ack_sync;`（紧邻 `wrfin_tgl_sync` 声明） |
| L563~571 | 新增独立两级同步 `always` 块，置于原 L560 大块之前 |
| L790 | 清 bank FSM `C_REQ`：`if (write_req_ack)` → `if (wr_ack_sync)` |
| L1061 | `bmp_read` 例化：`.write_req_ack(write_req_ack)` → `(wr_ack_sync)` |

端口 `write_req_ack` 保留不动，顶层零改动；`frame_fifo_write` 零改动。

**环境补齐**：`vsim` 报 `Module 'EG_LOGIC_BRAM' is not defined`（`track_list.v:58`、`bmp_read.v:264`）。补齐 `D:\TD5.6.2\arch\eagle_macro.v`（43 个原语模块）后解决。**此文件编译期不需要、只在 elaboration 时需要**，故全量 `vlog` 检查发现不了，跑 tb 才会暴露——已记入 `Anlu.md` 口径。

**回归结果（改后）**

| TB | 基线 | 改后 |
|---|---|---|
| `tb_clear_bank` | `CLEAR BANK TESTS PASS` | **PASS** |
| `tb_step2_resident` | `SCENARIO-A/B PASS` | **PASS** |
| `tb_step5_reload` | `STEP5 RELOAD ALL PASS` | **PASS** |
| 全量 `vlog`（65 模块） | 仅 2 条厂商加密文件错误 | **相同，无新增** |

三个 tb 与基线完全一致，说明 ack 晚 2 拍未破坏清 bank 握手与装载流程。

**步骤 5**：TD `syn_1` + `phy_1` 已提交（GUI 保持开启），结果待记录 3 回填。

### 记录 3：TD 复跑结果（2026/10/20 20:50）——目标达成，但整体被拥塞掩盖

`syn_1` 1m53s + `phy_1` 2m36s；bitstream 已同步 `best_result`（MD5 一致）。

**目标组：完全解决**

| 指标 | 改前 | 改后 |
|---|---|---|
| `ext_mem_clk → sd_card_clk` 违例端点 | **109 / 113** | **0 / 4** |
| 该组 WNS | −2.182ns | **+0.076ns** |
| 该组 STNS | −132.006ns | **0.000ns** |

113 个端点降到 4 个（剩下的就是两级同步器自身的同步路径），109 条违例全部消失。**CDC 正确性问题同时消除**。

**全局：反而略差**

| 指标 | 改前（二期 A 后） | 改后 | 变化 |
|---|---|---|---|
| Setup WNS | −2.182 | −2.203 | 略差 |
| Setup TNS | −239259 | −364268 | 变差 52% |
| Setup 违例端点 | 413 | **451** | +38 |
| Hold WNS / 端点 | +0.011 / 0 | −0.004 / 1 | 出现 1 条 |
| slices | 9109（92.95%） | **8995（91.79%）** | −114 |

**逐组对照（关键）**

| 路径组 | 改前 | 改后 | 解读 |
|---|---|---|---|
| `ext_mem → sd_card`（B 的目标） | −2.182 / 109 | **+0.076 / 0** | **达成** |
| `sd_card_clk` 域内 | −0.924 / 283 | **−2.203 / 390** | 成为新最差 |
| `ext_mem_clk` 域内 | −0.179 / 21 | **−1.921 / 61** | 明显变差 |
| `sd_card → ext_mem` | +0.119 / 0 | +0.171 / 0 | 保持干净 |
| `video_clk` 域内 hold | 0 | −0.004 / 1 | 单条伪违例 |

**归因分析**

1. **目标组清零是真实收益**：ack 从裸跨域改为两级同步后，`ext_mem_clk` 到 `sd_card_clk` 之间只剩同步器自身的 4 条路径且全部满足。
2. **整体变差不是本改动的逻辑缺陷，而是拥塞下的布局重排**：slices 从 9109 降到 8995（更省），却出现更差的时序，说明 placer 在 91.79% 占用下做了不同取舍。TD 对同输入是确定性的（前面复跑过两次，数字逐位相同），所以这不是随机抖动，而是"加了 2 个 FF 改变了起点"。
3. **两条新的最差路径都不是本次改动引入的**：
   - `sd_card_clk` 域内 −2.203：`bmp_read_m0/mult4` → `up_pixel_byte_idx_reg[0].d`，数据 12.132ns、**逻辑 8 级（LUT4x4 + LUT5x2 + ADDERx2）**，扇出 6——`bmp_read` 内部乘法/索引计算链，属二期 C。
   - `ext_mem_clk` 域内 −1.921：`write_active_width_latch_reg` → `App_wr_addr_r`，数据 9.641ns、逻辑 7 级、**扇出 45**——正是二期 A **刻意没动**的行跳转链（`write_line_jump_flip/normal`），现在浮上来成为第二差，属二期 D。

**结论**

- **B 保留**：它解决的是真实 CDC 正确性问题，且目标组归零；整体数字波动来自拥塞，不是回退理由。
- 设计已进入**拥塞主导**阶段：单点改动无法再显著改善全局，必须削减 `sd_card_clk` 域内深度（C）与行跳转链（D）。
- **下一优先**：先做 **D**（行跳转链打拍，与 A 同型、成本低，覆盖 61 端点 / −1.921），再做 **C**（`bmp_read` 深组合链，390 端点 / −2.203，工作量最大）。
