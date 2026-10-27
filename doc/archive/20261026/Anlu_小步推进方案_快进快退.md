# 小步推进方案：音乐快进 / 快退 ±10 秒（任务 5）

## 1. 背景与目标

`项目方案.md` §7 任务 5（2026/10/25 用户点名新增）。行为约定：
- 快进 10s；**超过末尾自动切下一首开头**；
- 快退 10s；**退到 0 就停在 0**（不回上一首）。

**本次不做**：不做变速播放、不做拖动进度条、不改频谱刷新率。

## 2. 当前代码事实（已核）

| 模块 | 现状 |
|---|---|
| `SD/fat32_chain_reader.v` | **支持任意起点**：`load_start` + `start_cluster` 载入簇链，之后按 `bmp_req/bmp_k` 顺序吐字节；反向不可走 |
| `SD/wav_stream_player.v` | 状态机 `W_IDLE/W_FLUSH/W_REQ/W_FILL/W_WAIT/W_DRAIN`；`chain_req/chain_k` 取字节，`sample_tick` 控制出样本，内部有音频 FIFO 与 `flush_req_toggle` 清空机制；对外有 `sample_counter`（已播样本数） |
| `SD/track_controller.v` | 负责选曲、记录 `start_cluster`、发出 `play_start/play_stop`，并维护右上角倒计时 |
| `top` | `audio_valid` 现由 `tone_dds` 提供（E19.14 起），WAV 播放器以它为配速；`wav_pcm/wav_playing` 参与音源 mux |

**关键约束**：FAT32 簇链是单向的，**没有反向链**；一次 10s = 48000×10×2B = **960,000 字节 ≈ 1875 个 512B 扇区**。

## 3. 改动步骤（建议两小步，各自可独立验收）

### 步骤 1：播放器支持"跳过 N 字节"（不改外部接口语义）

- `wav_stream_player` 增加 `skip_req`（脉冲）、`skip_bytes[23:0]`、`skip_reload`（是否先回到文件头重载簇链）；
- 进入 `W_SKIP` 状态：继续从 `chain_reader` 取字节但**不写入 FIFO**，字节计数到 0 后回到 `W_FILL`；
- **跳转后必须清空音频 FIFO**（复用现有 `flush_req_toggle`），否则残留样本会先播出来；
- `sample_counter` 与倒计时按跳过量相减/相加。

### 步骤 2：顶层按键与倒计时

- 交互（**待用户确认**，3 个键已占满）：建议 **切歌模式（SW3 向下 ON）下短按 KEY2 = 快退 10s、短按 KEY4 = 快进 10s**；该模式原本"短按无功能"，长按仍是切歌，互不冲突；
- 快进越过末尾 → 直接发"下一首"（复用现有 `track_cmd_next`）；
- 快退到 ≤0 → 停在 0；
- 倒计时跳变由 `track_controller` 按 ±10s 修正（需要核对它目前的计时口径）。

## 4. 验收方式

**我这边**：`vlog` 全量编译；若改动触及 `wav_stream_player` 状态机，先补/扩 tb（现有 `tb_wav_player_v2.v`）验证"跳过 N 字节后样本从正确位置继续、FIFO 无残留"；构建三门禁。

**用户上板清单**：
1. 切歌模式短按 KEY4 → 歌曲跳到 10 秒后（听感 + 倒计时同步），无爆音、无旧样本残留；
2. 短按 KEY2 → 退回 10 秒；连按多次到 0 后停住，不回上一首；
3. 快进超过末尾 → 自动切下一首并从头播；
4. 跳转期间画面不闪、频谱重新起跳；
5. 正常播放/切歌/面板/放大均无回归。

## 5. 回退点与风险

- 回退点：E19.15，MD5 `AE2621428F9E8CA49F1BE2053CDFB7A6`（`best_result` 当前即此版本；`sim/backups/` 另有 E19.14 备份）。
- 风险：跳转期间簇链重载 + FIFO 清空的时序若处理不当，会**爆音/错位**；退格只能"回文件头 + 跳过"，一曲 60 秒时最坏要跳过约 50 秒数据（≈ 2~4 秒等待），这是无索引表的固有代价。
- 可选优化（本次不做）：播放时记录每 10s 的簇号（≤60 项 BRAM），退格直接跳表，两端都变快。

## 6. 任务过程记录

（执行中追加）

## 7. 集成点（2026/10/26 03:00 勘察，供下次直接开工）

| 文件 | 关键信号 / 行号 | 说明 |
|---|---|---|
| SD/wav_stream_player.v | play_start(9) / cur_k / ytes_received | 需要新增 `start_sector[31:0]` 输入；play_start 时 `cur_k<=start_sector`、`bytes_received<=start_sector<<9` |
| SD/wav_stream_player.v | lush_req_toggle(70~) / W_FLUSH(198) | 复用现有清空机制，跳转后必须走一次 |
| SD/track_controller.v | player_start(18, 214) / 倒计时输出 | 需要新增 `seek_req/seek_fwd` 输入；内部做 停止→重算偏移→重发 `player_start`，并按 ±10s 修正倒计时 |
| SD/fat32_chain_reader.v | `C_PREP` / `cur_chain_pos < target_pos`(157) | **只能向前走**：load_start 可复位到链头，随后靠 mp_k 走到目标扇区；快退必须走这条 |
| SD/sd_card_bmp.v | u_wav_chain(982) / u_wav_player(1010) / wav_load_start(322) | 新增 top→此处的 `seek` 端口，把"重载簇链 + 带 start_sector 启动"串起来 |
| 	op_tf_hdmi_audio.v | k1_short_v/k2_short_v、`sw_key_mode` | 切歌模式（SW3=0）下短按 KEY2=快退、KEY4=快进；需与 zoom/track 的按键门控并列 |

**下次开工顺序**：①给 player 加 start_sector 并补 tb（不改变行为）；②track_controller 加 seek 状态机 + 倒计时修正；③sd_card_bmp 连线；④top 按键；⑤一次构建 + 上板。

- 2026/10/26 03:40 完成并上板验证：MD5 `935327DA0E04A6F354502F2649C44BBB`，用户确认切歌模式短按 ±10s、越界切下一首、切图模式回归均正常。实现见 §7 集成点。
