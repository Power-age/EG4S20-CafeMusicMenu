# Anlu 小步推进方案 时序收敛二期 C：sd_card 域内深组合链

> **来源**：二期 D 完成后（2026/10/20），剩余 424 个 setup 违例端点中 **410 个（97%）集中在 `sd_card_clk` 域内**，WNS −1.277ns。这是二期最后一块。
> **当前稳定点**：E15 + 一期约束 + 二期 A/B/D（已上板通过；Setup 424 EP / −1.277，Hold 2 EP / −0.011，slices 9009 / 91.93%）

---

## 1. 背景与目标

### 现状

`phy_1/final_timing.rpt`（D 后）抽样 10 条违例路径：

| 起点 | 条数 | 终点 | 数据延迟 / 逻辑级 |
|---|---|---|---|
| `bmp_read_m0/mult4` | 6 | `up_row_read_byte_cnt.ce`、`up_row_mem.cea`、`up_raw_x.ce`、`sel28` | 10.93~11.21ns / 6 |
| `u_chain/cur_cluster_reg` | 3 | `cur_cluster.ce`、`sd_addr[30]` | 10.95~10.97ns / 8~9 |
| `bmp_read_m0/width_reg[5]` | 1 | `up_row_read_byte_cnt.ce` | 10.93ns / 6 |
| （含打包混合） | | `seg_scan_m0/sel1.ce` | 11.19ns / 6 |

**两类真实链 + 一类打包噪声**：

1. **`bmp_read` 升采样行起始地址链**（占多数）
   `up_source_y` → `up_row_stride_product = source_row_stride × up_source_y`（MULT18）→ `+pixel_offset` → `+load_sector_latched` → `[31:9]` → 与 `sd_sec_read_addr` 比较 → 与 `up_row_read_byte_cnt < source_row_stride` 相与 → `up_row_wr_en` → 驱动 `up_row_mem.cea` 与 `up_row_read_byte_cnt.ce`（bmp_read.v L200~206）。

2. **`fat32_chain_reader` 的 phys 计算**
   `phys = data_start_r + ((cur_cluster - 2) << spc_shift_r) + sec_in`，其中 `sec_in = bmp_k & (spc_r-1)`；结果写入 `sd_addr`（fat32_chain_reader.v L161~163，`C_PREP` 状态内的命名块）。

3. **SLICE 打包噪声**：如起点在 `bmp_read/mult4`、终点却在 `seg_scan_m0/sel1.ce`（数码管扫描器，与图像通路无关）。这类与 E14 SDC 注释里记录的 `video_clk` 打包假路径同源，改逻辑消不掉。

### 本次目标

只处理上述**两类真实链**，打包噪声不作为目标（也不宜用 `set_false_path` 掩盖，因为无法逐条确认）。

### 关键约束：TB 覆盖现状

| 模块 | 现有 TB | 结论 |
|---|---|---|
| `fat32_chain_reader` | **`tb_chain_shim.v`**（场景1 连续链 1041 扇区、场景2 坏链报错） | **有覆盖**，可改 |
| `bmp_read` | **无**。`tb_clear_bank`/`tb_step2_resident`/`tb_step5_reload` 都是在 `sd_card_bmp` 层用 `force` 钉住 `bmp_ready`/`bmp_active_*` 等信号，**根本不进 `bmp_read` 内部** | **无覆盖**，改前必须先建 TB |

---

## 2. 拆分与推进顺序

### C1：`fat32_chain_reader` phys 预计算（先做）

**改法**：把 `(cur_cluster - 2) << spc_shift_r` 与 `data_start_r` 的合并预先寄存，`C_PREP` 里只做一次加法。

**时序障碍**：`cur_cluster` 在两处被赋值——`load_start`（← `start_cluster`）与 `C_FAT_DONE`（← `entry`）。若流水寄存器比 `cur_cluster` 晚一拍稳定，则 `C_FAT_DONE → C_PREP` 的下一拍会用到**上一个簇**的基址，地址算错。

**两种解法**：

| 解法 | 做法 | 风险 |
|---|---|---|
| **(a) 同步赋值** | 在 `cur_cluster` 赋值的那两处，同时给 `cluster_base_q` 赋对应新值（用 `start_cluster`/`entry` 直接算） | 无需改状态机；但把算术搬到 `entry → cluster_base_q.D` 这条路上，可能只是换个地方违例 |
| **(b) 加等待状态** | 新增 `C_PREP_W`，`C_FAT_DONE` 与 `load_start` 先进入它、停留 1 拍再进 `C_PREP`；`cluster_base_q` 持续寄存 | 结构清晰、时序更短；但改了状态机，需靠 `tb_chain_shim` 回归确认扇区序列不变 |

**倾向 (b)**：把长链彻底拆成两级寄存，且 `tb_chain_shim` 会直接校验 1041 个扇区的 `sd_addr` 序列，状态机改动有兜底。

### C2：`bmp_read` 乘法链（后做，需先建 TB）

**改法**：寄存 `up_row_stride_product`（MULT18 输出），使 `up_row_start_sector` 的计算只剩加法与比较。

**前置工作**：必须新建 `tb_bmp_read.v`——用假扇区存储喂一个最小 BMP（如 4×2、24 位），跑通头部解析 + 升采样行扫描，断言 `sd_sec_read_addr` 序列与 `bmp_data_wr_en` 输出。这是本项目第一次给 `bmp_read` 建 tb，工作量比 C1 大得多。

**风险**：`up_row_start_sector` 晚一拍会影响 `up_sector_past_start` 的比较，需确认行首 1~2 拍不会误判 `up_row_byte_active`（否则会漏写或多写一个像素字节）。

---

## 3. 验收方式

### C1

| 检查 | 判据 |
|---|---|
| `tb_chain_shim` 改前基线 | 场景1 `SCEN1 CONTIGUOUS PASS`、场景2 `SCEN2 BAD-CHAIN ERROR PASS` |
| 改后回归 | 同上，且**扇区数仍为 1041** |
| TD | `u_chain` 相关违例下降；全局 WNS / 端点数改善；slices 基本不变 |

### C2

| 检查 | 判据 |
|---|---|
| 新建 `tb_bmp_read` 基线 | 改前 PASS（`sd_sec_read_addr` 序列与像素输出符合手算） |
| 改后回归 | PASS 且序列逐项相同 |
| TD | `bmp_read` 相关违例显著下降 |

### 上板（每步单独）

- C1：图片装载与显示正常（簇寻址错会直接导致图错/图碎）。
- C2：升采样小图（PIC3 200×300）放大显示正确、无缺列/错行。

---

## 4. 回退点与风险

### 回退点

- 改前稳定版：**二期 D 完成态**（已上板通过；Setup 424 EP / −1.277，slices 9009）。

### 风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| C1 状态机加等待拍后时序或行为异常 | 簇地址错 → 图像错乱 | `tb_chain_shim` 校验 1041 扇区序列 |
| C1 解法 (a) 只是把违例搬家 | TD 无改善 | 优先用解法 (b) |
| C2 无 TB 就改 | 升采样路径静默错 | **必须先建 `tb_bmp_read`**，未建不改 |
| 打包噪声占比不明 | 即使两类链修完，端点数未必归零 | 接受；打包噪声不能用 false_path 掩盖 |
| 已到攻坚性价比拐点 | 从 653 → 424 已投入 4 步，剩 1.3ns 收益递减 | 由用户决定是否继续 |

---

## 5. 任务过程记录

（执行中追加，历史不改写）

### 记录 1：方案建立（2026/10/20）

- 完成 10 条抽样路径归类：6 条 `bmp_read` 乘法链、3 条 `u_chain` phys 链、1 条 `seg_scan` 打包噪声。
- 查明 TB 覆盖差异：`fat32_chain_reader` 有 `tb_chain_shim`，`bmp_read` **完全无 tb**（集成 tb 全在 `sd_card_bmp` 层 force）。
- 确认 C1 的唯一时序障碍是 `cur_cluster` 的两处赋值与流水延迟不对齐，给出 (a)/(b) 两种解法。

### 记录 2：C1 完成（2026/10/20 22:02）——目标达成，但 WNS 被 C2 链占住

**采用解法 (b)：新增等待状态 + 持续寄存簇基址**

`SD/fat32_chain_reader.v` 改动：

| 位置 | 内容 |
|---|---|
| L48~58 | 新增状态 `C_PREP_W = 4'd9` |
| L71 | 新增 `reg [31:0] cluster_base_q` |
| L127 | 每拍寄存 `cluster_base_q <= data_start_r + ((cur_cluster - 2) << spc_shift_r)` |
| L144~146 | 新增 `C_PREP_W` 分支：停留 1 拍后进 `C_PREP` |
| L169 | `phys = cluster_base_q + sec_in`（原为 `data_start_r + ((cur_cluster-2)<<shift) + sec_in`） |
| L138 / L215 | `load_start` 与 `C_FAT_DONE` 的成功分支改为进 `C_PREP_W` |

**为什么 1 拍够**：`cur_cluster` 在 T 拍更新后于 T+1 有效，`cluster_base_q` 用 T+1 的 `cur_cluster` 寄存、于 T+2 有效，`C_PREP_W` 恰好在 T+1 停留一拍，T+2 进入 `C_PREP` 时基址已就绪。

**回归**：`tb_chain_shim` 两场景均 **PASS**，扇区数仍为 1041。

**TD 结果（`syn_1` 3m + `phy_1` 6m49s）**

| 指标 | D 后 | **C1 后** | 说明 |
|---|---|---|---|
| `sd_card_clk` 域内违例端点 | 410 | **351** | −59 |
| 全局 Setup 端点 | 424 | **374** | −50 |
| Setup TNS | −208424 | **−186630** | −21800 |
| Setup WNS | −1.277 | −1.287 | 基本持平 |
| `u_chain/cur_cluster` 抽样违例 | 3 条 | **0 条** | **目标达成** |
| Hold | −0.011 / 2 | −0.044 / 4 | 略差（伪违例量级） |
| slices | 9009（91.93%） | 9009 | 不变 |

**结论**

1. **C1 目标达成**：`u_chain` 的 phys 链违例从抽样中完全消失，端点数减 50、TNS 改善 10%。
2. **WNS 持平的原因清楚**：最差路径仍是 `bmp_read_m0/mult4 → up_row_mem.wea`（BRAM 写使能），数据 11.082ns、逻辑 6 级（LUT5x2 + ADDERx2 + LUT4x1 + LUT2x1）——即 C2 那条乘法链，占剩余违例的绝大多数。
3. **Hold 的 4 条为伪违例**（−0.044~−0.011ns），不影响功能。

**剩余工作 = C2**：需要先新建 `tb_bmp_read.v`（本工程首次覆盖该模块），再寄存 `up_row_stride_product`。这是二期里唯一还需要从零建测试台的一步。

### 记录 3：C2 尝试——TB 先行拦下一次功能回归（2026/10/20 22:40）

**第一步：建 `sim/tb_bmp_read.v`（本工程首次覆盖 `bmp_read`）**

- 构造 20×20 / 24bpp 最小 BMP（54 字节头 + 1200 字节像素）放进 4 个假扇区，扇区模型仿照 `tb_chain_shim` 的协议。
- 目标显示尺寸用 64×48（缩小以加快仿真）；期望几何：等比放大到 48×48、`offset_x=8`、`offset_y=0`、写入 2304 像素。
- 自校验：装载无错、`wr_pixels == active_width × active_height`。

**第二步：发现 BRAM 宏在仿真中是空壳**

首次跑出 `undef_px = 2304`（全部像素为 X）。查明 `D:\TD5.6.2\arch\eagle_macro.v` 里的 `EG_LOGIC_BRAM` **只有端口与参数、没有任何行为体**（`endmodule` 紧跟参数列表），仿真中读出一律为 X。这解释了工程里现有 tb 为何普遍只验控制流、不验数据。

按工程既有先例（`osd_buffer.v` 的 `OSD_BUFFER_SIM`、`font_rom.v` 的 `FONT_ROM_SIM`、`track_list.v` 的 `TRACK_LIST_SIM`）给 `bmp_read` 的 `up_row_mem` 增加 `` `ifdef BMP_ROW_MEM_SIM `` 行为模型分支。**宏未定义时仍走原 `EG_LOGIC_BRAM` 实例，综合网表完全不变。**

**第三步：黄金基线（改动前）**

| 项 | 值 |
|---|---|
| `active_w/h` | 48 / 48（与手算一致） |
| `offset_x/y` | 8 / 0 |
| `pixel_count` | 2304 |
| `wr_pixels` | 2304 |
| `defined_px` / `undef_px` | 2304 / 0 |
| `sum_data` | **−1605858304** |
| `xor_data` | **32** |

**第四步：实施 C2 并被 TB 拦下**

改动：新增 `up_row_stride_product_q` 寄存一拍，`up_row_start_calc` 改用寄存值。

回归结果：几何与像素数不变（48×48、2304、defined 2304），但 **`sum_data` −1605858304 → −1891600044、`xor_data` 32 → 14008466**。

即**升采样取到的行数据变了**——打一拍使 `up_row_start_calc` / `up_row_start_sector` 滞后，而它们分别在 `up_sector_start_offset`（L608）与 `sd_sec_read_addr`（L931）处被锁存，锁存时刻距 `up_source_y` 更新不足两拍，于是取到了上一行的起始扇区。

**第五步：回退并确认**

撤销改动后黄金基线逐位恢复（`sum_data` 回到 −1605840304 同值、`xor_data` 回到 32）。**当前 RTL 与已上板版本功能等价，无需重新出包。**

**结论与后续**

- C2 不能简单打拍，必须像 C1 那样**给状态机加一拍等待**，保证 `up_source_y` 更新后 ≥2 拍才锁存起始扇区。
- 现在具备验证手段：`tb_bmp_read` + 黄金校验和 + `BMP_ROW_MEM_SIM` 行为模型，改完一跑即可判定是否等价。
- 该改动属 FSM 级修改，风险高于 A/B/D/C1，建议单独作为一步推进。

### 记录 4：路线 2（换布局种子）实测无效（2026/10/20 22:51）

`DefaultFlow.tcl` 的 `prepare` 已支持 `phyWildParams`，据此在 `phy_1/settings.cfg` 追加 `set phyWildParams {place seed N}` 即可换放置种子，无需额外目录（比 `MultiSeed.tcl` 更省事）。

| 配置 | Setup WNS | Setup TNS | 违例端点 | Hold | 线长 |
|---|---|---|---|---|---|
| **默认（无 seed）** | **−1731** | **−231281** | **364** | −11 / 5 | **1772984** |
| seed 7 | −2867 | −323836 | 462 | −12 / 7 | 1895976 |
| seed 11 | −1695 | −281791 | 405 | −25 / 11 | 1874096 |

- seed 11 的 WNS 虽略好 36ps，但违例端点 405 vs 364、TNS 差 5 万、hold 违例 11 条 vs 5 条，**综合更差**。
- 恢复默认后重建，QoR 与之前**逐位相同**（确定性得到再次验证）。
- **结论：默认放置种子即当前最优，换种子无收益。** 此路不通，不再浪费时间。

### 记录 5：C2 改进思路（未实施）——用累加器彻底去掉乘法

记录 3 的失败说明"给乘法输出打拍"会改变取样时刻。换个方向：**根本不在组合路径上做乘法**。

观察：`up_row_start_calc = pixel_offset + source_row_stride × up_source_y`，而 `source_row_stride` 在整个升采样期间是**常量**，`up_source_y` 每行只加 1。因此可改为**累加**：

- 新增寄存器 `up_row_calc_acc`，载入时置为 `pixel_offset`；
- 每当 `up_source_y` 自增时，同步执行 `up_row_calc_acc <= up_row_calc_acc + source_row_stride`；
- `up_row_start_calc` 直接取 `up_row_calc_acc`（已是寄存器值）。

这样 `mult4`、以及后面两个加法器全部从关键路径消失，且**取值与原来完全等价、不产生任何时序偏移**——不像打拍那样会改变锁存时刻。

**验证手段已就绪**：改完跑 `tb_bmp_read`，`sum_data` 必须仍为 **−1605858304**、`xor_data` 仍为 **32**、`defined_px` 2304。

**需先确认两处**：`up_source_y` 自增的位置（`bmp_read.v` 约 L668~669 附近）、以及 `pixel_offset` 在载入时刻是否已稳定。

### 记录 6：C2 累加器方案实施成功（2026/10/20 23:01）——二期最大单步收益

**实施内容**（`SD/bmp_read.v`）

| 位置 | 改动 |
|---|---|
| L100 | 新增 `reg [35:0] up_row_calc_acc;` |
| L201 | `assign up_row_start_calc = up_row_calc_acc;`（删除原乘法与两级加法） |
| L590 | `ST_LOAD_WAIT` 收到 `write_req_ack` 时 `up_row_calc_acc <= {4'd0, pixel_offset};` |
| L671 | `ST_UP_REPEAT` 中 `up_source_y` 自增的**同一条件**下 `up_row_calc_acc <= up_row_calc_acc + {18'd0, source_row_stride};` |
| L153 | 删除已成死逻辑的 `wire [33:0] up_row_stride_product;` |

`pixel_offset` 全工程仅 L298 一处赋值（恒 54，BMP 标准头长），故载入时刻已稳定。

**功能回归（黄金校验和）**

| 项 | 黄金基线 | 累加器版 |
|---|---|---|
| `active_w/h` | 48 / 48 | 48 / 48 |
| `offset_x/y` | 8 / 0 | 8 / 0 |
| `wr_pixels` | 2304 | 2304 |
| `defined_px` / `undef_px` | 2304 / 0 | 2304 / 0 |
| `sum_data` | −1605858304 | **−1605858304** |
| `xor_data` | 32 | **32** |

**逐位相同**——累加器与 `pixel_offset + stride × y` 数学等价，且因为是寄存器累积、不是打拍，**不产生任何取样时刻偏移**，避开了记录 3 的坑。

**TD 结果（`syn_1` 2m49s + `phy_1` 6m29s）**

| 指标 | C2 前 | **C2 后** | 变化 |
|---|---|---|---|
| Setup WNS | −1731ps | **−689ps** | **+1042ps** |
| Setup TNS | −231281ps | **−35650ps** | **降 85%** |
| Setup 违例端点 | 364 | **147** | **−217** |
| Hold WNS | −11ps | −9ps | 持平 |
| Hold 违例端点 | 5 | **2** | −3 |
| 线长 | 1772984 | 1844104 | +71120 |

**逐组**

| 路径组 | C2 前 | C2 后 |
|---|---|---|
| `sd_card_clk` 域内 | 351 / −1.287 | **134 / −0.689** |
| `ext_mem_clk` 域内 | 14 / −0.361 | **13 / −0.591** |
| 其余组 | 均干净 | 均干净 |

**新最差路径已换人**：`height_reg[17] → fit_scale_base_reg[7]`，数据 10.409ns、逻辑 7 级（ADDER×4 + MULT18×1）、扇出 47——即 BMP 头解析阶段的**等比适配计算链**（`aspect_lhs/rhs` 的 32 位乘法 + `fit_calc_*`），只在每张图解析时跑一次，不在像素通路上。

**二期累计（从 E15 起点）**：Setup 违例端点 **653 → 147**（−506），Setup WNS **−6.846 → −0.689**（改善 **9.9 倍**）。

**待上板验证**：C2 改的是小图放大路径的行起始偏移来源，必须确认 PIC3 放大显示与原版一致（无缺行/错行），PIC1/PIC2/PIC4 无回归。

### 记录 7：C2 上板出现错行，已回退（2026/10/20 23:12）——重要教训

**上板结果**：用户反馈"小图放大品质稍微变差，有一定的错行，但总体正确；KEY1 复位后不消失"。

**关键矛盾**：C2 在仿真中与原始算式**逐位等价**（`sum_data` −1605858304、`xor_data` 32 完全一致，2304 个像素数据一个不差），却在硬件上产生了可见的行错位。

**结论：逻辑等价 ≠ 硬件等价。** 该版本仍有 147 个违例端点（WNS −0.689）；把乘法换成累加器后综合结果重新洗牌，虽然全局变好，但 `bmp_read` 升采样数据通路上的某条路径可能变得更临界，在硅片上表现为取错行。复位不消失也印证这是确定性的时序问题，不是上电竞态。

**处理**：已完整回退 C2（`up_row_calc_acc` 及其三处引用、`up_row_stride_product` 恢复原式），重新构建后 QoR **逐位复现**已验证版本（WNS −1731 / TNS −231281 / 364 端点 / 线长 1772984），bitstream 已同步 `best_result`。

**保留的资产**（不随回退丢失）：

- `sim/tb_bmp_read.v`：本工程首个 `bmp_read` 测试台，含黄金校验和。
- `bmp_read.v` 的 `BMP_ROW_MEM_SIM` 行为模型分支（宏未定义时网表不变）。
- 累加器方案本身在 RTL 层是正确且更优的（省掉 MULT18 + 两级加法），只是**单靠它不足以消除该数据通路的临界**.

**对后续的启示**：剩余违例**不是纯指标问题**，它们会在硅片上产生真实缺陷。要重试 C2，必须同时保证 `bmp_read` 升采样数据通路（`up_row_mem` 写使能/读地址、`up_raw_x`/`up_emit_src_x` 相关链）没有临界路径，否则会重演错行。也就是说：**改一处必须连带确认整条通路，不能只看全局 WNS 改善**。

### 记录 8：回退版仍有"轻微错行"——查证为最近邻缩放的固有现象（2026/10/20）

用户反馈：回退版（逻辑上等同于此前的已验证版本，QoR 逐位一致）**仍有轻微错行**，怀疑是更早存在的问题。

**验证方法**：把 `tb_bmp_read` 的源图改为 20×30、目标 64×48，使纵向缩放比恰为 **1.6**（与 PIC3 的 300→480 相同），并新增断言：每个输出行首次写入时，`up_source_y` 必须等于 `floor(out_y × 源高 / 输出高)`。

**结果**：

```
active_w/h = 32 / 48      map_rows = 48 (expect 48)      map_err = 0
```

**48 个输出行全部命中期望源行，零误差。** 即升采样的纵向取行逻辑是严格正确的 Bresenham，不存在取错行的缺陷。

**那"错行"是什么**：1.6 倍最近邻放大时，源行被复制的次数必然不均匀——按 `0,0,1,1,2,3,3,4,5,5,...` 的规律，**部分源行占 2 个输出行、部分占 1 个**，60% 复制两次、40% 一次。视觉上就表现为**行距时疏时密**，容易被看成"错行"。横向同理。

这是最近邻算法的**固有特性**，不是缺陷，也不是本轮任何改动引入的。台账 §6 第 6 条早已记录"缩放质量未优化：当前为最近邻，大图缩小与小图放大都存在画质损失空间"。

**结论**：回退版功能正常，无需再改；若要改善观感，需要做**缩放质量优化**（双线性插值等），那是独立的功能任务，不是时序问题。

**测试台黄金基线（新参数 20×30）**：`active 32×48`、`offset_x 16`、`wr_pixels 1536`、`defined 1536`、`sum_data 1692050432`、`xor_data 184`、`map_err 0`。
