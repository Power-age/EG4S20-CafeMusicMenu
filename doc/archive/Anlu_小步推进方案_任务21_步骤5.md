# 小步推进方案：任务 21 步骤 5 —— 背景清黑与整体验收（升 E8）

> 上位方案：`Anlu_小步推进方案_任务21.md`。前置：步骤 1~4 均已上板通过。

## 0. 范围调整（2026/10/05 上板核对后，用户确认）

- 开发板 SD 卡座只接 4 根 SPI 线、**无卡检测（CD）引脚**；SD 初始化 FSM 成功后 sd_init_done 锁存、**拔卡不回落**。因此：
  - **拔卡**：系统状态不变（四图常驻 SDRAM），画面保持、仍可切图、不卡死 —— 已满足任务 12"不卡死/可保持"。
  - **重插自动重载不做**（用户明确"不用管"）。
- 本步聚焦解决上板发现的真实缺陷：**图片有效区之外的背景显示彩色噪点**。

## 1. 缺陷根因（已核对代码）

- `sd_card_bmp.v`：`write_len = bmp_active_pixel_count`；`frame_fifo_write` 写起始地址带 active offset（`oy*640+ox`），只写 active 像素数，按行跳转。
- 因此 **bank 内 active 窗口之外的地址从未被写入**，保留 SDRAM 上电随机值 → 背景显示随机彩色噪点。
- 满屏 640x480 图（森林、山湖）无背景 → 干净；小图（ANLU logo）、竖图（城市夜景，两侧填充区）暴露噪点。
- 任务 21 顺序装载改造后才出现（双缓冲时代写满整帧/反复覆写，背景被覆盖）。

## 2. 解决方案：上电先清 4 bank 为黑，再顺序装载 active

在 `sd_card_bmp.v` 内**复用现有写通道**（wfifo + frame_fifo_write），新增一个"清 bank"状态机：SD 初始化完成后（与 SD 扫描**并行**）把 4 个 bank 各整帧写 0（307200 字），完成后置 clear_done；顺序装载仅在 clear_done 后启动。active 像素随后覆盖到已清黑的 bank，背景保持纯黑。

- 不改 `frame_read_write.v` / `frame_fifo_write.v` / `bmp_read.v`，不新增 IP、不新增可综合文件。
- clear 与 SD 扫描并行（clear 用 SDRAM、扫描用 SD，互不干扰）；clear 4bank 约几十 ms，通常不增加首图等待。

## 3. 改动点（全部在 sd_card_bmp.v）

1. **新增 clear FSM**（sd_card_clk 域）：
   - 状态：C_IDLE →（sd_init_done 且 !clear_done）→ C_REQ(对 cbank) → 等 write_req_ack → C_RV(撤 req) → C_FEED(write_en 持续送 0) → 等 write_finish → C_NEXT(cbank+1；cbank=3 则 clear_done=1、C_FIN)。
   - 输出：clear_active、clear_req、clear_feed、cbank[1:0]、clear_done。
2. **写端口 mux（clear_active 时）**：
   - write_req：`clear_active ? clear_req : bmp_write_req`（bmp_read 的 write_req 改连内部 wire `bmp_write_req`）。
   - write_en：`clear_active ? clear_feed : bmp_data_wr_en`。
   - write_data：`clear_active ? 32'd0 : {bmp_data[23:0],8'b0}`。
   - write_len：`clear_active ? 21'd307200 : bmp_active_pixel_count`。
   - write_active_width/height：clear 时 640/480；offset_x/y：clear 时 0。
   - write_buf_idx：改为 wire，`clear_active ? cbank : load_write_buf_idx`（原 reg 改名 load_write_buf_idx，主 FSM 赋值处同步改名）。
3. **顺序装载触发条件加 `clear_done`**（发起装载分支与"空判 ar=1"分支都加），避免 clear 未完成提前置 ar。
4. **复位/重扫清 clear 状态**：`!sd_init_done` 分支与 scan_kicked 分支清 clear_done、cbank、cst=C_IDLE。
5. write_req_ack 为共享输入（bmp_read 与 clear FSM 都读）。

## 4. 本地验证

- `vlog` 0 error；新增 `sim/tb_clear_bank.v`：行为化 frame_fifo_write 握手（write_req→ack→撤销→finish），断言：
  1. clear 阶段共 4 次写请求，write_buf_idx 依次 0,1,2,3；
  2. clear 期间 write_len=307200、write_data=0、active=640x480 offset0；
  3. clear_done=1 后顺序装载方可触发。
- 回归 tb_step2（A/B）、tb_step5、tb_resident_switch（18 项）全 PASS；完整 hdl_source（47 v）0 error，改动文件 0 新增 warning。

## 5. 上板整体验收（用户执行）

1. 上电装载：位4 走到 F。
2. **背景**：切到 logo、竖图，active 区之外背景应为**纯黑、无彩色噪点**；竖图两侧纯黑。
3. 切图：reveal / fade 正常、零加载延迟、不撕裂；编号、sw_con1 反向、key2 自动每约 1s 走转场。
4. 拔卡：画面保持、不卡死（重插不要求重载）。
5. 回归：亮度/对比度、OSD、音频电平条、HDMI 显示正常。
6. **判据不下调**：四图常驻、切图零延迟、不撕裂 + 背景纯黑，必须同时满足。

## 6. 收尾（验收通过后）

- 任务 21 各步骤方案件移入 `doc/archive/`。
- `项目进度.md`：登记本步与整体验收结论，稳定版本升 **E8**（E8 = E7 + 任务 21 四 bank 常驻帧缓存，含背景清黑），更新回退链表与下一步。
- 同步 `开发任务清单.md`：任务 21 标记完成。

## 7. 范围冻结

- 不做重插自动重载、交叉 fade（任务 22）、错误码 OSD（任务 14）、子目录/LFN。

## 8. 任务过程记录

- 2026/10/05：上板核对，确认拔卡 sd_init_done 不回落、无 CD 引脚；经用户确认放弃重插自动重载，聚焦背景噪点。
- 2026/10/05：完成本方案（背景清黑）设计，用户审批同意；备份 `Project_backup_20261005_preclear`。
- 2026/10/05：完成 sd_card_bmp RTL（clear FSM + 写端口 mux + write_buf_idx 改 wire + 装载条件加 clear_done + sd_init 拉低自动复位 clear）。完整 hdl（47 v）编译 **0 error**。
- 2026/10/05：新增 `sim/tb_clear_bank.v`，**CLEAR BANK TESTS PASS**（buf 0,1,2,3、len=307200、data=0、geom 640x480 offset0、clear_done=1）。
- 2026/10/05：回归全 PASS —— tb_step2（SCENARIO-A/B）、tb_resident_switch（18 项）、tb_step5_reload（STEP5 RELOAD ALL PASS）。
- 待办：TD 重新综合生成 bit，上板整体验收（重点：背景纯黑无噪点）。
