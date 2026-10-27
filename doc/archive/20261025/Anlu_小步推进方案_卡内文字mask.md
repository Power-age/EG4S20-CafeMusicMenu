# 小步推进方案 · 任务 1 卡内文字 mask 通路

- 建立时间：2026/10/25 15:45
- 对应 `项目方案.md` §7 的 **任务 1（当前主线）**
- 当前基线：**E19.0**，MD5 `B1B5B1D9CD98BD5CC5F2A1485BD2F006`，slices 95.21%，`video_clk` +13.117 / `sd_card` −0.253 / `ext_mem` −0.136
- 回退点：E19.0 固件 + `sim/backups/ui_v4_20261024/` 源码快照

## 1. 当前代码事实（必须先认清的一个关键点）

### 现有 OSD 是"字符网格"，装不下位图

`osd_buffer_overlay.v` 读的是 **256 列 × 80 行的字符缓冲**（每格一个字符码 + 2bit 属性），再由字体 ROM 逐像素展开成 8×8 字形，屏幕 2× 放大。
渲染器通过 `req_ascii / req_x / req_y` 往这个字符网格里写**字符**。

**结论：`TXT*.BIN` 是 240×128 的位图，塞不进字符网格。** 它必须走一条**独立的像素层通路**：
另开一块 BRAM 存位图，按屏幕坐标读 2bit alpha，再与主画面混合——本质上和"横幅底条"类似，只是颜色来自位图而不是常量。

### 素材（已上卡）

| 文件 | 规格 | 用途 |
|---|---|---|
| `TXT11~TXT42.BIN` | 240×128 / 2bit / 7680 B | 8 块，每页左右卡各一块 |
| 打包格式 | 行优先，每字节 4 像素，从左到右占 bit[1:0]/[3:2]/[5:4]/[7:6] | 与 `make_clean_menu_and_masks.py` 一致 |
| `PIC1~4.BMP` | 1280×960 / 无文字 | 卡片空白区留白 |

### 需要先查清的未知

- **BRAM32K 余量**：16 块 × 4KB = 64KB。8 块 mask 共 60KB（要 15 块），若全驻留几乎吃满。
  **倾向方案：只驻留当前页的 2 块（15KB ≈ 4 块），翻页时重载**——省 BRAM 且翻页本来就有一次重绘。
- 现有 OSD 字符缓冲、字体 ROM 各占多少 BRAM（BRAM9K / BRAM32K），必须先从综合报告确认。

## 2. 具体改动（拆三步，每步一次构建）

### 步骤 1：raw 文件 → BRAM 装载器（只做装载与静态显示）

1. **装载器**（新模块 `mask_loader.v`，跑在 `sd_card_clk` 域）：
   - 复用现有 FAT32 扫描得到的簇链，按文件名 `TXTxy.BIN` 找到起始簇；
   - 顺序读扇区，把 7680 字节流式写入 BRAM（写口 32bit 或 8bit，视 BRAM 原语而定）；
   - 完成后置 `mask_ready`。
2. **像素层**（新模块 `mask_overlay.v`，`video_clk` 域）：
   - 两个窗口：左卡 x 50~289、右卡 x 350~589，y 331~458（由 240×128 按屏幕 1:1 换算，具体坐标待与覆盖层对齐后定）；
   - 按 `x_local/y_local` 算出 BRAM 读地址 → 取 2bit alpha；
   - 输出 `mask_rgb/mask_alpha/mask_vld` 给顶层，在 `O_display_rgb` 前做最后一次混合（**必须排在面板/横幅之后**，优先级最高，避免被其它层覆盖）。
3. **混合公式**：`out = bg*(1-a) + text*a`，`a = 0/85/170/255`（2bit 四档）；文字色用暖白 `#F4EDE2`（与信息条一致）。
4. **本步不做滑动**，只验证"位图能从卡进 BRAM 并正确叠在卡片空白区"。

### 步骤 2：滑动 + 翻页联动

1. 翻页时（`e2_disp_buf_sync` 变化）→ 触发重载当前页 2 块 mask；
2. 装载完成后启动滑入：左卡 x 偏移从 `-240` 递增到 `0`，右卡从 `+240` 递减到 `0`，**每 2 帧走 1 像素**（约 0.5 秒滑完，可调）；
3. 滑入期间若再次翻页 → 中止当前动画、重新装载；
4. 打开设置面板 → 隐藏卡内文字（`mask_en=0`）；
5. 相邻像素边界做 1px 软边（可选，看观感）。

### 步骤 3：删旧字幕通路 + 频谱上移

1. 删 `subtitle_render.v` 实例、`ticker_text.mif` 引用、覆盖层里的底部字幕窗口（`stxt_*` 相关约 250 LUT）；
2. 频谱区由 y 407~471 上移到 y 380~470（占用原字幕带空间，柱子变高）；
3. 更新 `工程交互使用说明文档.md` 的屏幕元素表。

## 3. 验收方式

### 仿真

- `tb_mask_loader`：喂一个假的 7680 字节流，校验 BRAM 内容与末尾地址；
- `tb_mask_overlay`：给定 2bit 图样，逐点比对混合输出的 RGB（四档 alpha 各取一点）。

### 构建

- 黑盒 0；slices ≤ 96%；`video_clk ≥ 0`、`sd_card ≥ −0.6`、`ext_mem ≥ −0.8`；
- 步骤 3 后记录 REG/LUT 下降量（预期 −250 LUT 左右）。

### 上板

1. 翻页后左右卡文字**从两侧滑入**并停在卡片空白区正中；
2. 文字清晰、无锯齿（2bit 四档 alpha 生效）；
3. 打开菜单时文字消失，关闭后重新滑入；
4. 频谱变高（步骤 3 后）；
5. 左上 `PAGE n/4`、右上 `歌名 -MM:SS` 不受影响。

## 4. 回退点与回退步骤

- 每步单独构建、单独记录；出问题只回退该步；
- 全量回退：E19.0（`B1B5B1D9…`）+ `sim/backups/ui_v4_20261024/`；
- 步骤 1/2 是**新增模块**，回退只需在 `top` 里去掉实例、把 `O_display_rgb` 的混合选择位关掉，不动其它逻辑。

## 5. 风险与待确认

| 风险 | 影响 | 应对 |
|---|---|---|
| BRAM32K 余量不足 | 8 块 mask 无法全驻留 | 已倾向"只驻留当前页 2 块"，翻页重载 |
| 装载器要新写 FAT 读逻辑 | 工作量 | 复用现有 BMP 读扇区通路，只换"目标从 FIFO 变成 BRAM 写口" |
| 混合层插入位置 | 若排在面板之前，会被面板盖住；排在最后又可能盖住面板 | 优先级定为"最高"，但**菜单打开时强制关闭 mask** |
| 滑入与翻页竞争 | 动画中途翻页 | 翻页即中止动画、重载 |
| 面积 | 新增 loader + overlay 约 +150~250 LUT | 步骤 3 删旧字幕可抵消 |

---

## 6. BRAM 勘察结果（2026/10/25 15:50，综合报告实查）

现有 `EG_LOGIC_BRAM` 实例（综合 log 的 `HDL-1007 elaborate` 行）：

| 用途 | 配置 | 备注 |
|---|---|---|
| OSD 字符缓冲 | 2bit × 4096，PDPW | 双端口，字符网格 |
| `spec_cos/sin/samp_zero` | 16bit × 1024 各一 | 频谱查表 |
| `font_data` | 8bit × 1024 | 16px 字体 |
| `font5x7_data` | 8bit × 1024，**IMPLEMENT="32K"** | 5×7 字体（已占 BRAM32K）|
| `ticker_text` | 8bit × 256 | 旧字幕（任务 1 步骤 3 会删）|
| `track_names` | 8bit × 256 | 曲名 |
| 其它 | 8bit × 512、24bit × 1024、8bit × 1024 等 | 音频/其它 |

**容量换算**：一块 BRAM32K = 32Kbit = **4KB**。
- 单块 mask 7680 B = 61,440 bit ≈ **2 块 BRAM32K**；
- 当前页 2 块 mask ≈ **4 块 BRAM32K**（16 块中的 4 块）；
- 若 8 块全驻留 ≈ 15 块（几乎吃满，**不采用**）。

**实现选型**：用 `EG_LOGIC_BRAM`，`DATA_WIDTH 32 / DATA_DEPTH 2048`（= 8192 B > 7680 B ✓），MODE 选可写简单双口；每块 mask 一个实例，共 2 个实例。

## 7. 下一步的具体动作（下一轮从这里开始）

1. `mask_loader.v`：在 `sd_card_clk` 域，按文件名 `TXT<t><k>.BIN` 查 FAT 目录 → 取起始簇 → 顺序读扇区 → 转为 32bit 写入 BRAM（7680 B = 1920 个 32bit 字 → 地址 0~1919）；
2. `mask_overlay.v`：`video_clk` 域按窗口坐标算地址（`addr = y_local * 60 + x_local[7:2]`，再取字节内 2bit），输出 alpha；
3. 顶层：在 `O_display_rgb` 最后一级混入（菜单打开时 `mask_en=0`）；
4. **新增 .v 必须同时登记**：`src/td_project/*.al`、`Runs/syn_1/*.prj`、`Runs/phy_1/*.prj`，否则综合报黑盒（`HDL-1007`/`HDL-8007`）；
5. 先做步骤 1（静态叠加），验证后再做滑动。

---

## 8. 步骤 1a 执行记录（2026/10/25 16:00）

### 已完成

1. **`txt_mask.mif`**：由真实 mask `TXT11.BIN` 转换而来（240×128 2bit → 2048×32bit ROM，未用地址填 0），34 KB；
2. **`mask_overlay.v`**：窗口几何（左卡 x 50~289、右卡 x 350~589、y 331~458）+ 地址换算（`addr = (ly*240 + lx) >> 4`，字内像素 `(lin & 15)`，2bit alpha 取 `(q >> {piw,1'b0}) & 3`）+ 四档 alpha 混合；ModelSim 编译通过。

### 必须先纠正的一点（下一轮第一件事）

`mask_overlay.v` 目前用 `reg [31:0] mem [0:2047]` + `$readmemh` 来装 ROM。**这在 TD 里不会按预期变成 BRAM**——本工程既有 ROM 的统一写法是：

```
`ifdef XXX_SIM
    $readmemh(...)
`else
    EG_LOGIC_BRAM #(... DATA_WIDTH_A=32, DATA_DEPTH_A=2048, INIT_FILE=".../txt_mask.mif" ...)
`endif
```

若直接用 `$readmemh`，综合器可能把 2048×32 的存储**铺成分布式 RAM（几十块 LUT）**，面积直接爆掉。

**而且这一步正好与步骤 1b 衔接**：换成 `EG_LOGIC_BRAM` 后，把它的**写端口**接给 loader，就能从"卡装载"平滑替换"静态 ROM"，叠加层逻辑一行都不用改。

### 下一轮的具体动作

1. 把 `mask_overlay.v` 的 `reg mem[]` 换成 `EG_LOGIC_BRAM`（32bit × 2048，SP/PDPW，`INIT_FILE="../../user_source/hdl_source/txt_mask.mif"`）；
2. 在 `top` 里实例化，接在 `O_display_rgb` 的最后一级（`panel_vis` 接菜单可见信号，`mask_en` 先接常数 1，`slide_l/slide_r` 先接 0）；
3. **新增 .v 与 .mif 必须同时登记**：`src/td_project/*.al`、`Runs/syn_1/*.prj`、`Runs/phy_1/*.prj`；
4. 构建 → 确认黑盒 0、面积增量可接受 → 烧录 → 上板看左上卡区域是否出现"手冲埃塞俄比亚 ¥28"字样（内容来自 TXT11）。

---

## 9. 步骤 1b 执行记录（2026/10/25 16:10）

### 已完成

1. **`mask_overlay.v` 的存储已改为 `EG_LOGIC_BRAM`**（32bit × 2048，`INIT_FILE=txt_mask.mif`，`IMPLEMENT` 默认即 2 块 BRAM32K），并用 `ifdef MASK_SIM` 保留仿真侧的 `$readmemh`；`vlog +define+MASK_SIM` 编译通过。
2. **视频链路已摸清**（这是接线必须的前提）：

```
wave 频谱叠加      : vout_data_base  -> vout_data_wave
效果（亮度/对比/淡入）: vout_data_wave  -> vout_data_pre
OSD 字符叠加       : vout_data_pre   -> vout_data
AXIS 转换（最终出口） : I_rgb = vout_data
```

**结论：mask 层要插在 `vout_data` 与 `video_rgb_to_axis_640x480` 之间**（即唯一一处 `I_rgb(vout_data)`，第 1345 行）。

### 卡住的地方（下一轮第一件事）

mask 叠加需要**显示坐标 x/y（0~639 / 0~479）**，而顶层现有像素计数器分散在 wave/OSD 两段（`wave_de`、`osd_de`、`osd_rd_x/osd_rd_y` 由谁生成还没确认）。
**不能猜**——猜错会导致"文字叠在错误位置"且难以排查。

下一轮动作：
1. 查 `osd_rd_x` / `osd_rd_y` 的生成源（大概率是顶层的一个 `x_cnt/y_cnt` 计数块），复用它作为 mask 的坐标输入；
2. 实例化 `mask_overlay`（`.de` 用对应的 de、`.panel_vis(menu_panel_vis)`、`.mask_en(1'b1)`、`.slide_l/r(0)`）；
3. 把 `video_rgb_to_axis_640x480` 的 `.I_rgb` 从 `vout_data` 改为 mask 的输出；
4. 登记 `.v`（`mask_overlay.v`）与 `.mif`（`txt_mask.mif`）到 `.al` + 两份 `.prj`；
5. 构建 → 黑盒 0 → 面积增量 → 烧录 → 上板看左卡区域是否出现"手冲埃塞俄比亚 ¥28"。

---

## 10. 步骤 1 完成（2026/10/25 16:22，上板确认）

- 构建：MD5 `493475D033AEA486FC071F615E93E44C`，slices **95.47%**、`video_clk` **+11.784 / 0 违例**、`sd_card` −0.452、`ext_mem` −0.482、黑盒 0；LUT 仅 +6（TD 把混合逻辑优化得很省）。
- **接线**：`mask_overlay` 接在 OSD 之后、AXIS 转换之前（`vout_data` → `vout_data_mask`），坐标取 `video_x_cnt[9:0]` / `video_y_cnt`，`de=osd_de`，`panel_vis=menu_panel_vis`。
- **上板结果**：左上卡片区域出现暖白文字「手冲埃塞俄比亚 ¥28 / 柑橘与花香 口感干净」，**位置大致正确**。
- 登记：`mask_overlay.v` 已加入 `.al` 与两份 `.prj`；`txt_mask.mif` 随 `INIT_FILE` 被引用（TD 直接打包，不需要列入文件表）。

## 11. 下一阶段的取舍（需要用户拍板）

要"每页显示各自的文字"，必须让 8 块 mask 都能被访问。BRAM32K 只有 16 块（4KB/块），单块 mask 7680B ≈ 2 块：

| 方案 | BRAM | 画质 | 工作量 |
|---|---|---|---|
| **A. 8 块全驻留 / 2bit** | 15 块（几乎吃满）✗ | 4 档 alpha | 不可行 |
| **B. 当前页 2 块 / 2bit + 卡装载器** | 4 块 | 4 档 alpha（最好）| 要写 FAT 装载器（大） |
| **C. 8 块全驻留 / 1bit** | 8 块 ✓ | 无 alpha（硬边）| 只需生成 MIF，当天可验收 |
| **D. 每卡 1 块 ROM 装 4 页 / 1bit** | 2 块 ✓✓ | 无 alpha | 同上，最省 |

推荐：**先做 C（或 D）拿到"翻页文字正确"的可验收结果，再决定要不要为 alpha 上装载器**。
