# Anlu 小步推进方案 · 任务 20（FAT32 完整版：簇链跟随）

## 1. 背景与目标

对应 `项目方案.md` 任务 20「FAT32 按文件名读取 4 张图」。当前稳定点 E6 内的是**方案 B**：扫描器只取首簇转起始 LBA，bmp_read 从该 LBA 起扇区线性 `+1`，假设文件连续。反复删除/替换不同大小图片后文件碎片化或复用已删簇，线性读跨进错误簇读到陈旧头/像素，正常图被误跳（重新格式化卡即正常，已证明与 RTL 无关）。

本次单一目标：**让“拖图片进 SD 卡（根目录、PIC1~PIC4.BMP）即可正常读”，不挑碎片**。

做法分两块：
1. 扫描器沿根目录 FAT 簇链扫**完整**根目录（不再只读第 1 个扇区），跳过删除项/长名项；
2. 新增**簇链翻译垫片**，把 bmp_read 输出的“文件内相对扇区号”翻译成跟随 FAT 簇链的真实物理 LBA。

本次**不做**（防范围蔓延）：子目录、长文件名匹配（只跳过 LFN、仍按 8.3 匹配 PICn.BMP）、多级目录、非 ASCII 名称、音频/WAV 改动、bmp_read 缩放引擎改动。

## 2. 当前代码事实

### `src/user_source/hdl_source/SD/fat32_volume_scanner.v`
- 已解析 BPB 并输出几何参数：`sectors_per_cluster`、`fat_start_lba`、`data_start_lba`、`max_cluster`，内部有 `root_cluster`、`root_lba`、`sectors_per_cluster_shift`。
- 根目录只读**一个扇区**：`ST_ROOT_REQ`（约 379–384 行）发一次读 → `ST_ROOT_WAIT`（385–392）→ `ST_DIR_SCAN`（393–398）：`resource_valid==4'hf` 才 `ST_FINISH`，否则直接 `ERR_RESOURCE_MISSING`。
- 目录项在 `ST_ROOT_WAIT` 内按 `sector_byte_index[4:0]` 逐字节在线解析（241–305 行），匹配 PIC1~4 并锁存簇号/大小。
- 已有 `sector_buffer[0:511]`、`le16/le32` 函数可复用。

### `src/user_source/hdl_source/SD/sd_card_bmp.v`
- 扫完时把首簇转起始 LBA 存 `img_sector0~3`（528–539 行）：`data_start + (cluster-2)*spc`。
- 加载时把 `load_sector`（物理 LBA）喂给 bmp_read（实例 697–736，`.load_sector` 在 712 行）。
- SD 口仲裁：`scan_phase ? scanner : bmp`（158–160 行）；500ms 超时/abort 逻辑在 175–198 行。

### `src/user_source/hdl_source/SD/bmp_read.v`（本次不改）
- `load_sector_latched <= load_sector`（772 行）。
- 普通路径：`sd_sec_read_addr <= sd_sec_read_addr + 1`（905 行）。
- 放大路径：`up_row_start_sector = load_sector_latched + up_row_start_calc[31:9]`（202 行），`ST_UP_PREP` 把地址设为它（917 行）；访问随 `up_source_y` 单调向前。
- 头部/像素的字节内偏移与文件物理地址无关。

**关键结论**：若把 `load_sector` 喂 **0**，bmp_read 输出的 `sd_sec_read_addr` 即**文件内相对扇区号 k**（普通路径从 0 递增；放大路径 = 文件偏移>>9），内部比较仍自洽。垫片据此翻译，bmp_read 零改动。

## 3. 改动步骤

### 步骤 1：扫描器扫完整根目录（改 `fat32_volume_scanner.v`，端口不变）
- 新增根目录遍历计数 `root_sec_in_cluster`（当前簇内已读扇区，0~spc-1）与当前根簇寄存器 `root_cluster_cur`。
- 每个根扇区读完后（替代直接进 `ST_DIR_SCAN`）：
  - `resource_valid==4'hf` → `ST_FINISH`；
  - 若在线解析遇到目录项首字节 `0x00`（目录结束）→ 全找到则 `ST_FINISH`，否则 `ERR_RESOURCE_MISSING`；
  - 若 `root_sec_in_cluster < spc-1` → 地址 `root_lba+1`、计数 +1，再发读；
  - 若当前根簇扇区已读完 → 读 FAT 表取根目录下一簇（新增 `ST_ROOT_FAT_REQ/ST_ROOT_FAT_WAIT`）：
    - FAT 扇区 = `fat_start_lba + (root_cluster_cur>>7)`，表项偏移 = `(root_cluster_cur&7)<<2`，读 4 字节掩码 `0x0FFFFFFF`；
    - 表项落在 `0x0FFFFFF8~0x0FFFFFFF` = 根链结束 → 全找到 finish，否则 `ERR_RESOURCE_MISSING`；
    - 表项 `<2` 或 `>=max_cluster` → `ERR_SECTOR`/链错误；
    - 合法下一簇 → `root_cluster_cur<=next`、`root_lba = data_start +(next-2)*spc`、`root_sec_in_cluster<=0`，发读。
- `0xE5` 删除项、`0x0F` LFN 项：在线匹配本就不会命中 PICn，保持忽略；显式以首字节判定，不进入匹配。
- FAT 扇区读取复用 `sector_buffer`（根扇区解析已完成后）。

### 步骤 2a：新增簇链垫片并在连续文件上验证
- 新增 `src/user_source/hdl_source/SD/fat32_chain_reader.v`：
  - 输入：`load_start`、起始簇、`fat_start_lba/data_start_lba/spc/spc_shift/max_cluster`；bmp_read 侧请求 `bmp_sec_read` + 相对扇区 `bmp_sec_addr(=k)`；sd_card_top 侧返回数据/valid/end。
  - 输出：到 sd_card_top 的 `sd_sec_read/sd_sec_read_addr`（物理）；到 bmp_read 的 data/valid/end/error。
  - 目标簇序号 = `k>>spc_shift`，簇内扇区 = `k & (spc-1)`；跨簇时读 FAT[当前簇]（FAT 扇区/偏移同上），缓存 1 个 FAT 扇区，相邻簇同扇区不重读；物理 LBA = `data_start +(簇-2)*spc + 簇内扇区`。
  - 坏链：表项越界（≥max_cluster）、提前 EOC、自循环 → 输出 error。
- 改 `sd_card_bmp.v`（只改接线）：
  - `img_sector*` 改为存**起始簇**（可改名 `img_cluster*`）；加载时 `.load_sector` 喂 `32'd0`，起始簇接垫片；
  - 加载阶段 SD 口改由垫片驱动（扫描阶段仍给 scanner）；500ms 超时/abort 包裹垫片请求；
  - `.al`（`src/td_project/HDMI1.4b_Transmitter_v1.0.al`）登记 `fat32_chain_reader.v`。
- 连续文件上垫片结果必须与方案 B 完全一致（无回归）。

### 步骤 2b：碎片文件上板验证
- 不格式化，反复删换不同大小图片制造碎片（或拷贝大量文件再删以逼出非连续分配），四张图（含小图 PIC3、大图 PIC4）正确显示、循环正确。

## 4. 验收方式

- 本地（只做语法 + 自检测仿真，**不跑 TD syn/phy/bitstream**）：
  - `iverilog -g2001 -Wall -i`，加入实际存在的 `E:/Anlu/TD_6_2_1/arch/eagle_macro.v`（旧文档 `D:/TD5.6.2` 路径已失效）。
  - 自检测试台 + Python 生成 FAT32 镜像与期望 LBA/字节：
    - 扫描器：根目录跨 ≥2 簇，含 0xE5/0x0F/0x00，断言簇号、大小、不误报错；
    - 垫片：连续文件、碎片文件（簇链跳簇）、坏链（越界/自循环/提前 EOC），断言物理 LBA 序列与逐字节数据，坏链必报错。
- 上板（用户执行 TD 与上板），按步骤 1 → 2a → 2b 顺序，每步现象正确再进下一步：
  - 步骤 1：四张图、编号正常（无回归）；根目录塞 >16 杂项文件后仍找到 PIC1~4；
  - 2a：连续文件显示/切图/轮播/亮度对比度/方向/OSD/拔卡恢复均无回归；
  - 2b：不格式化制造碎片后四张图全部正确、循环正确（决定性场景）。
- 若 2b 失败，先把垫片“当前簇 / FAT 错误 / 链位置”接空闲数码管补可观测手段，再定位，不盲改 RTL。

## 5. 回退点与风险

- 改动前稳定版本：**E6（方案 B）**，回退链见 `项目进度.md` 3.1。
- 步骤 1 异常 → 回退 `fat32_volume_scanner.v`；步骤 2a 异常 → 回退 `sd_card_bmp.v` 接线并移除垫片实例（bmp_read 未改，无需回退）。
- 风险点：
  - 垫片在加载中插入 FAT 读，需保证 bmp_read 等待期间握手不产生“幽灵读”（参照 scanner 电平请求、sd_sec_read_end 后再换地址）；
  - 新增 FAT 访问路径可能受既有 setup WNS -6699ps 影响；单因素推进，上板是最终判据；
  - 判据不下调：2b 不通过不算任务 20 完成。

## 6. 任务过程记录

- 2026/10/04：方案经用户确认，建立本推进方案，任务拆为步骤 1 / 2a / 2b；尚未改动 RTL。
