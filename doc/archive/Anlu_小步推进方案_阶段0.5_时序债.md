# Anlu 小步推进方案：阶段 0.5 时序债专项（fit_calc 链）

> **来源**：《Anlu_后续整体推进方案》阶段 0.5。2026/10/21 19:09 从 E16 回退后启动。
> **基线**：E16 重建版（`MD5 486F14E1`，已上板验证功能正常）。slices 9078（92.63%）、BRAM 36/64、DSP 12/29、**Setup WNS −707ps / 212 端点**、Hold −8ps / 5 条。

---

## 1. 要解决什么

当前最差路径（V2-10 构建时暴露）：

```
sd_card_bmp_m0/bmp_read_m0/width_reg[24] → sel39.mi[0]
数据 12.891ns，逻辑 6 级（ADDER×4 + MULT18×1 + LUT3 + LUT4），扇出 47
```

出现在 `ST_HDR_FIT_PREP` 状态：

```verilog
fit_wide       <= (aspect_lhs > aspect_rhs);
if (aspect_lhs > aspect_rhs) begin
    fit_scale_base <= width;
    ...
end else begin
    fit_scale_base <= height;
    ...
end
```

**根因**：`width`/`height` 是 **32 位**寄存器，而

```verilog
assign aspect_lhs = {32'd0, width}  * {32'd0, target_height};   // 64 位 × 64 位，截断到 64 位
assign aspect_rhs = {32'd0, height} * {32'd0, target_width};
```

做成了 **64×64 乘法再截断**，TD 用 MULT18 + 4 级加法器拼出来，路径里还带着 `width` 的**第 24 位**（高位参与运算）。这一拍还要同时驱动 3 个寄存器（`fit_wide`、`fit_scale_base/step`、`fit_calc_limit`），扇出 47。

**危害**：这条链本身约 12.9ns（时钟周期 10ns），**怎么放都违例**。只要布局稍差就把它顶到最前面，导致整体 WNS 在 −0.7 ~ −7.5ns 之间乱跳，功能也可能因其它路径违例而失效（10/21 的 `b` 故障即此类）。

---

## 2. 修改方案（按代价从低到高，逐级验证）

### 步骤 A：乘法收窄到 16×16（首选）

`width`/`height` 来自 BMP 头，实际图片尺寸 ≤ 8192；显示缓冲只有 640×480，超过 65535 的图根本无法显示。因此把参与比较的维度**饱和到 16 位**：

```verilog
wire [15:0] width16  = (width[31:16]  != 16'd0) ? 16'hFFFF : width[15:0];
wire [15:0] height16 = (height[31:16] != 16'd0) ? 16'hFFFF : height[15:0];
assign aspect_lhs = width16  * bmp_height;   // 16×16 → 32 位（单 MULT18）
assign aspect_rhs = height16 * bmp_width;
```

- **饱和处理**保证超大尺寸不会退化成 0（比直接截断安全）
- 位宽从 64 降到 32，乘法从 64×64 降到 16×16 → 预估削掉 6~8ns
- **不改语义**：宽高比比较在正常图片上与原来完全一致

**验收**：`tb_bmp_read` 黄金校验和不变（`sum_data 1692050432`、`xor_data 184`），TD WNS 明显改善。

### 步骤 B：乘积打一拍（若 A 不够）

把 `aspect_lhs/rhs` 在 `ST_HDR_IMAGE` 状态寄存一版，`ST_HDR_FIT_PREP` 只用寄存值比较：

```
ST_HDR_IMAGE:    aspect_lhs_q <= aspect_lhs;  aspect_rhs_q <= aspect_rhs;
ST_HDR_FIT_PREP: if (aspect_lhs_q > aspect_rhs_q) ...
```

把「乘法 + 比较 + 3 个寄存器扇出」拆成「乘法→寄存器」和「比较→寄存器」两段。

### 步骤 C：拆 `fit_calc_acc` 加法链（若仍不够）

`fit_calc_acc_next = fit_calc_acc + fit_scale_step` 是 32 位加法，且与 `fit_calc_pending/emit` 的比较串在一起。可先寄存加法和，再用寄存结果比较：

```
fit_calc_sum_q <= fit_calc_acc + fit_scale_step;   // 只做加法
fit_calc_emit  <= (fit_calc_sum_q >= fit_scale_base);  // 下一拍比较
```

需要 FSM 等待拍配合（`ST_HDR_FIT_RUN` 已有 `fit_calc_done` 判据，加一拍不影响功能）。

---

## 3. 验收门禁

| 项 | 判据 |
|---|---|
| `tb_bmp_read` | `sum_data 1692050432` / `xor_data 184` / `map_err 0`（与基线逐位一致） |
| 全量 `vlog` | 无新增错误 |
| TD 构建 | 路由成功（日志无 `PHY-8023`/`RUN-8102`，bitstream 时间戳更新） |
| **时序** | **Setup WNS ≥ −1200ps**（目标 −400ps 以内）、违例端点 ≤ 300 |
| 资源 | slices ≤ 93%、BRAM 36、DSP ≤ 12 |
| 上板 | 图片加载、切图、轮播正常，数码管不报 A/b/c/d |

**每一级单独构建验证，不一次改完。**

---

## 4. 回退点与风险

| 项 | 说明 |
|---|---|
| 回退点 | E16 重建版（`MD5 486F14E1`，已上板验证） |
| 改动面 | 仅 `bmp_read.v` 的 3 条 assign（步骤 A）；B/C 才动 FSM |
| 风险① | 饱和处理改动语义边界，需确认正常图片路径不受影响（TB 覆盖） |
| 风险② | 任何 RTL 改动都会重排布局，可能出现"改好了这条、别的变差"→ 按 Anlu.md 规则：先查放置种子，再判断是否真回归 |

---

## 5. 过程记录

（执行中追加）

### 记录 1：步骤 A + B 实施完成（2026/10/21 19:58）

**改动**（仅 `bmp_read.v`）

| 步骤 | 改动 |
|---|---|
| A | `aspect_lhs/rhs` 由「32 位维度 64×64 乘法截断」改为「**16 位饱和后 16×16 乘法**」：`width16_aspect = (width[31:16]!=0) ? 16'hFFFF : width[15:0]`，再 `* bmp_height` / `* bmp_width`；wire 位宽 64→32 |
| B | 新增 `aspect_lhs_q/rhs_q`，在数据通路块的 `ST_HDR_RANGE` 拍寄存乘积；`ST_HDR_FIT_PREP` 改用寄存值比较，把「乘法→比较→3 个寄存器」拆成两段 |

**过程中踩的坑**：步骤 B 首次把寄存赋值写进了**状态机 always 块**，与数据通路块的复位赋值构成多驱动，TD 报 `HDL-8007 net 'aspect_lhs_q[31]' is constantly driven from multiple places`，**综合失败**（且 `phy_1` 会用旧 `gate.db` 继续跑出"看起来正常"的相同数字）。修正为在数据通路块新增 `ST_HDR_RANGE` 分支后通过。**教训：syn 失败不会中断流程，必须看日志/`.read_design.error.f`。**

**验证**

- `tb_bmp_read`：`sum_data 1692050432` / `xor_data 184` / `map_err 0` —— 与基线**逐位一致**
- 综合：无错误，LUT 15631（79.75%）、BRAM 36
- **fit_calc 链已不在任何违例路径中**（原 `width_reg[24] → sel39` 消失）

**TD 结果（同一网表换种子差异极大）**

| seed | Setup WNS | TNS | 违例端点 | Hold |
|---|---|---|---|---|
| 5 | −3498 | −149401 | 182 | −11 / 2 |
| **1（采用）** | **−386** | **−4961** | **32** | −20 / 5 |
| 3 | −492 | −11888 | 67 | −20 / 7 |

**采用 seed 1**：slices 8999（**91.83%**）、BRAM 36、DSP **10**（省了 2 个乘法器）、线长 1776728，bitstream `MD5 44461D9E`。

**与 E16 基线对比**

| 指标 | E16 | 现在 | 变化 |
|---|---|---|---|
| Setup WNS | −707ps | **−386ps** | +321ps |
| Setup TNS | −47976ps | **−4961ps** | 降 90% |
| 违例端点 | 212 | **32** | −180（−85%） |
| slices | 92.63% | **91.83%** | −0.8% |
| DSP | 12 | **10** | −2 |

**门禁判定**：WNS −386 ≥ −1200 ✓、端点 32 ≤ 300 ✓、slices ≤93% ✓、BRAM 36 ✓、DSP ≤12 ✓ → **全部通过**。

**新的最差路径**：`frame_fifo_write_m0/write_cnt[10] → write_cnt[10].ce`，11.382ns（ADDER×6，布线占 65%），属 `ext_mem_clk`（8ns 周期）。这是下一个可优化目标，当前不是阻塞项。
### 记录 2：上板验证通过（2026/10/21 20:0x）

用户上板确认：**图片加载、切图、放大/缩小、冷上电、音乐/波形/状态栏均正常**，数码管第 6 位不报调试码。

**阶段 0.5 收尾**：本任务完成，方案件可归档。当前稳定版 = E17（`MD5 44461D9E`）。