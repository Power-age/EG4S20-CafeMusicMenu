# Anlu 小步推进方案：任务 12

## 1. 背景与目标

对应 `Project/doc/项目方案.md` 任务 12。本次目标是为 SD 扇区读取增加 500ms 无响应保护：发起一次扇区读取后，如果既没有数据完成也没有扇区结束信号，超时后主动结束当前请求，向对应上层报告错误，并让系统回到可恢复路径，避免 scanner 或 BMP 加载永久卡住。

本次不新增错误 OSD、不修改 SD SPI 底层协议、不改变任务 10 已通过的坏图头校验重试策略、不引入看门狗或 FAT32 链跟踪。错误文字显示属于任务 14，系统级看门狗属于任务 26。

## 2. 当前代码事实

- 当前稳定交付包含任务 9 的严格 DIB 校验和任务 10 的坏图重试/跳过逻辑；两项均通过任务 10 集成版本验收，相关方案已归档。
- `Project/src/user_source/hdl_source/SD/sd_card_sec_read_write.v`：
  - `sd_sec_read` 为读请求电平；收到请求后进入 `S_CMD17`，随后进入 `S_READ`。
  - `sd_sec_read_data_valid` 只在 `S_READ && block_read_valid` 时有效。
  - `sd_sec_read_end` 只在 `S_READ_END` 时有效。
  - 当前没有读超时计数器，也没有向 `sd_card_top` 输出读错误。
- `Project/src/user_source/hdl_source/SD/sd_card_top.v`：仅转发 `sd_card_sec_read_write` 的读数据、数据有效和结束信号，没有错误端口。
- `Project/src/user_source/hdl_source/SD/sd_card_bmp.v`：
  - scanner 和 `bmp_read` 共用 `sd_sec_read`、地址、数据、valid、end 接口；由 `scan_phase` 仲裁。
  - scanner 阶段由 `scn_read_lvl` 保持读请求，`scn_sec_done` 接共享 `sd_sec_read_end`。
  - `scn_sec_error` 当前硬接 `8'd0`，所以 scanner 无法收到读错误。
  - BMP 阶段由 `bmp_sec_read` 进入共享接口，任务 10 的 `bmp_load_error` 只覆盖头校验失败，不覆盖 SD 读无响应。
- `Project/src/user_source/hdl_source/SD/fat32_volume_scanner.v` 已有 `sector_error` 输入，并在引导扇区/root 目录结束处检查非零错误后进入 `ERR_SECTOR`；因此 scanner 侧可以复用现有错误接口，不必新增 scanner 错误协议。
- 100MHz 时钟下 500ms 为 50,000,000 个周期，计数器至少需要 26 位；为避免边界歧义使用 `localparam integer SD_READ_TIMEOUT_CYCLES = 50_000_000` 和 26 位计数器。

## 3. 改动步骤

### 阶段 A：共享读取超时监视

1. 在 `sd_card_bmp.v` 的共享扇区仲裁层增加超时计数器，仅在一次实际读请求已被拉起且未收到 `sd_sec_read_end`/错误清除时计数。
2. 计数达到 500ms 时生成一个周期的 `sd_read_timeout_pulse`，清除当前 scanner/BMP 读请求电平，避免底层读请求永久保持。
3. 超时计数在读结束、读请求撤销、SD 初始化未完成或复位时清零。
4. 确保 scanner 阶段和 BMP 阶段共用同一计数器，但不在 `scan_phase` 切换时误继承上一笔请求的计数。

### 阶段 B：向两个消费者报告

1. scanner 阶段将超时脉冲转换为 `scn_sec_error` 的一次错误结果，并保证 scanner 能进入已有 `ERR_SECTOR` 收尾路径。
2. BMP 阶段将超时脉冲转换为加载失败事件，接入任务 10 已有的重试/跳过恢复；不改变正常 `bmp_load_error` 头校验失败行为。
3. 若共享 SD 读底层在超时后仍晚到 `sd_sec_read_end`，需要用请求代次/忙标志确保该迟到结束不会误结算下一次读取。

### 阶段 C：本地检查与差异核对

1. 检查 scanner/BMP 两条路径的错误脉冲时序和端口连接，确认无组合环路、悬空错误输入或重复驱动。
2. 使用项目既定 `iverilog -g2001 -Wall -i`，加入 `D:/TD5.6.2/arch/eagle_macro.v` 检查 `sd_card_bmp` 及相关 SD 模块。
3. 不执行 TD `syn_1`、`phy_1` 或 bitstream，由用户在 TD 中构建和上板。

## 4. 验收方式

### 本地检查

至少验证相关 RTL 语法通过；保留项目既有 timescale、厂商宏和浮空端口 warning。若新增计数器宽度或比较常量引发综合器告警，应在上板前先修正。

### 上板验证

1. 正常插卡启动、图片显示、手动切图、自动轮播和任务 10 坏图恢复无回归。
2. 运行中拔出 SD 卡或制造读请求无响应：约 500ms 后系统不永久卡住。
3. BMP 加载阶段无响应：任务 10 恢复路径能收到失败并按既有规则重试/跳过，上一张已提交画面保持。
4. scanner 阶段无响应：scanner 能结束当前扫描并进入已有错误收尾，不在上电阶段永久停留。
5. 重新插卡后的恢复行为必须按实际实现验证；若当前版本只做到退出卡死而未做到重新初始化，需要如实记录为遗留，不把判据下调。

## 5. 回退点与风险

- 回退点：任务 10 上板通过版本，即任务 9/10 集成验收后的稳定版本。
- 优先整体回退本方案涉及的 `sd_card_bmp.v` 以及必要的 `sd_card_top.v`/`sd_card_sec_read_write.v` 改动，不回退已归档方案正文。
- 主要风险是共享仲裁层超时与真实 SD 结束信号的竞争，可能造成下一笔读取被错误结束；必须保证超时清理和迟到结束隔离。
- 500ms 计数按 100MHz 工程时钟定义；若实际 SD 控制器使用其他时钟域，不能直接复用该阈值，需先确认时钟口径。
- 本次先处理“超时退出并报告错误”，不承诺插卡后完整重新初始化；重新初始化若需要独立改动，另行建立小步方案。

## 6. 任务过程记录

- 2026/09/27：任务 9/10 的集成坏图验证完成并归档；读取任务 12 定义和 SD 读、scanner、BMP 仲裁代码。
- 2026/09/27：确认底层读接口没有错误输出，scanner 的 `scn_sec_error` 当前硬接 0；任务 12 的最小落点应在 `sd_card_bmp` 共享扇区仲裁层统一监视并分流错误。
- 2026/09/27：完成共享读超时计数、scanner/BMP 错误分流、底层读 abort 和重新初始化路径；本地 `iverilog` 检查通过，仅保留既有 warning。
- 2026/09/27：用户上板观察到初版超时 abort 后重新插卡仍需复位；原因是底层只回到 `S_WAIT_READ_WRITE`，没有重新执行 SD 初始化。已修正为 abort 回到 `S_IDLE` 并清零 `sd_init_done`，使重新插卡后自动重走初始化和 FAT32 扫描；修复后尚待上板确认。
- 2026/09/27：用户上板进一步确认：初版重新初始化会清空 `display_valid`，导致切图中拔卡后黑屏且状态码回到 0；重新插卡后也会因首图路径回到 `PIC1`。本次同任务修订将保持最后一帧和 `img_idx/disp_buf_idx`，重新扫描仅恢复 SD 访问，不自动提交 `PIC1`。
- 待执行：修改 `sd_card_bmp.v` 的 `!sd_init_done` 清理分支和重新扫描启动分支，完成本地检查后等待再次上板验收。
