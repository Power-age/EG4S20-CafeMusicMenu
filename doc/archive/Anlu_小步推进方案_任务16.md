# Anlu 小步推进方案 · 任务 16：WAV 流式播放

> 对应任务：`项目方案.md` 第四批「音频链路」任务 16
> 创建日期：2026/10/06
> 前置稳定点：E8（任务 21 四 bank 帧缓存已通过）
> 教程参考：`doc/完赛系列/第11讲：WAV音频播放/`（wav_stream_player.v 等）

## 1. 目标与验收判据

**目标**：从 TF 卡流式播放根目录 `MUSIC.WAV`，播放期间替换现有测试音，播完回到测试音；不卡顿、不爆音，不影响四图常驻、切图与转场。

**验收判据（不下调）**：
1. 能从 HDMI 听到 `MUSIC.WAV` 的完整音乐，连续不卡顿、不爆音；
2. 播放期间四图常驻、零延迟切图、转场、编号、自动播放等无任何影响；
3. 一首播完自动回到测试音；
4. 无 MUSIC.WAV、拔卡或读取出错时不卡死，回落到测试音。

## 2. 现状链路（已核实）

- **视频**：四图常驻 SDRAM（E8），切图零延迟。
- **音频链**：
  `PLL_HDMI_AUDIO → audio_mclk(12.288MHz) → hdmi_audio_tone_i2s_64fs(测试音, I2S) → I2S_receiver → audio_valid(48kHz 单拍脉冲)+audio_left/right_data(24bit) → HDMI transmitter(48K)`。
- **SD 读取**：`sd_card_bmp.v` 内例化 `sd_card_top`（唯一 SPI 物理通道），对外是单扇区读接口（sd_sec_read / addr / data / data_valid / end）。
  现有仲裁 mux：`scan_phase ? 扫描器请求 : 图片 chain_reader 请求`（sd_card_bmp.v 行 197~204）。
- **簇链翻译**：`fat32_chain_reader.v`，接口为「文件起始簇 + bmp_req + 文件内相对扇区 k → 物理 sd_req/sd_addr，返回 to_bmp_data/valid/end/error」，可再例化一份给 WAV 复用。
- **扫描器**：`fat32_volume_scanner.v`，按 8.3 文件名匹配 `PICn.BMP`（行 270~277），输出 resource_valid[3:0]、resource0~3_cluster/size；在 resource_valid==4'hf（四图找全）时存在提前结束扫描的路径（行 407/436/455）。

## 3. 音频文件准备

- 用 PC 工具把任意 WAV 转换为 **48kHz / 16bit / 单声道 / 小端裸 PCM**（无 WAV 头），命名 `MUSIC.WAV` 拷入卡根目录，与 PIC1~PIC4.BMP 同目录。
- 第一版 FPGA 不解析 WAV 头，从文件第 0 扇区即 PCM 数据开始读。
- 转换脚本：工程 `python/` 下若无对应脚本则新增一个（make_audio_corpus 类）。

## 4. 增量架构

1. **扫描器扩展**：新增对 `MUSIC.WAV` 的 8.3 匹配，输出 `music_valid / music_cluster / music_size`；结束条件改为继续扫到 WAV（或扫完根目录），不再四图找全即停。
2. **sec 通道三源仲裁**：mux 由「扫描 / 图片」扩为「扫描 / 图片 / WAV」；WAV 用新例化的 `fat32_chain_reader`（wav_chain_reader）做簇链翻译。WAV 仅在 `all_resident` 后、前两源空闲时才占用通道。
3. **新增 `wav_stream_player`**（基于教程适配本工程 sec 时序）：
   - 写侧（sd_card_clk 100MHz）：逐扇区按「文件内扇区 k」请求，经 wav_chain_reader → sec mux；收字节、小端组装 16bit 样本写入双口 BRAM 循环缓冲（4096×16=8KB）。
   - 读侧（audio_mclk 12.288MHz）：以 I2S_receiver 的 `audio_valid`（48kHz 单拍）为采样节拍，从 BRAM 取 16bit 样本；缓冲不足时输出静音但 valid 不断。
   - 读写指针格雷码 + 2FF 跨时钟域同步。
4. **top 音源 mux + 播放控制**：WAV 播放中选 WAV PCM（16bit→24bit：{sample,8'b0}；左右声道复制），否则选 I2S_receiver 测试音；输出给 HDMI transmitter。常驻完成（all_resident）后自动播放，播完（stream_end）停止、回测试音。

## 5. 分步实施（每步：备份→改→编译→仿真/上板）

| 步骤 | 最小交付 | 验证 |
|---|---|---|
| 1 | 扫描器识别 MUSIC.WAV（music_valid/cluster/size + 结束条件） | tb / 上板确认扫到 |
| 2 | sec mux 扩三源 + 新增 wav_chain_reader | tb 按簇链读 WAV 扇区 |
| 3 | 新增 wav_stream_player（写侧+BRAM+读侧） | tb 验证组装/缓冲/下溢 |
| 4 | top 音源 mux + 播放控制接线 | 上板听连续音乐、无回归 |

## 6. 风险与注意

- 扫描器提前结束路径（行 407/436/455）必须改，否则目录顺序不利时会漏扫 MUSIC.WAV。
- SPI 单通道三源不可并发：WAV 用 all_resident 门控，与图片装载严格错开。
- 8KB 缓冲吸收约 12.5 倍速率差（TF 突发 ~1.2MB/s vs 音频 96KB/s）；下溢静音、不拉低 valid。
- 加密 SDRAM IP、官方/现有图片视频链路一律不改动；WAV 不经过 SDRAM，直接 SD→BRAM→HDMI。
- 第一版不解析真实 WAV 头、不做音量调节（任务 18）、不做三音源完整切换（任务 17）。
