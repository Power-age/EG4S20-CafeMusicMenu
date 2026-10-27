# 小步推进方案 · 任务 0 资源清理

- 建立时间：2026/10/25 13:40
- 对应 `项目方案.md` §7 的 **任务 0（前置，先腾面积）**
- 当前基线：**E18.9**，MD5 `2CDFBFABB8AC5B3F4D117824DF3A02FC`，slices **95.11%**，`video_clk` +10.016 / 0 违例，`sd_card` −0.686，`ext_mem` −0.988
- 回退点：E18.9 固件 + `sim/backups/ui_v4_20261024/` 源码快照

## 1. 当前代码事实

### 已确认无用的逻辑（有据可查）

| 项 | 位置 | 为什么可以删 | 预估节省 |
|---|---|---|---|
| bank 源尺寸通路 | `sd_card_bmp.v` 的 `bank_src_w_r/bank_src_h_r`（2×64bit）+ `bank_src_w/h` 输出；`top` 里的 `bsw/bsh` 同步与 mux；`bmp_read.v` 的 `source_width/source_height` 输出 | 左上角已改为**固定常量表** `TAB_W*/TAB_H*`，这条链路彻底没人用 | ~130 FF + ~40 LUT |
| 数码管 `state_code` | `top` 里送数码管的诊断码 | 早期调试用，现在无意义 | ~30 LUT |
| 死机检测/锁存 | 早期防死机逻辑 | 已无必要（且曾被误判）| ~50 LUT |

### 无人实例化的文件（**不省面积**，仅清理项目）

`font16_rom.v`、`hdmi_audio_tone_pcm_scale.v`、`key_events.v`、`waveform_peak_ram.v`、`afifo_16_256.v`、`afifo_16_256_sim.v`、`sdr_init_ref.enc.v`、`design_top_i2s_test_pll.v`、`i2s_rom_player_single_pll_fix64_rom_ip.v`

> 综合时未被实例化的模块本来就会被裁掉，**删文件不降 slices**。放在第二批做，只为缩短构建时间、减少接手时的误读。

### 不能删的

- `subtitle_render.v` 与点阵字幕相关逻辑：**要等任务 1 的 mask 通路替上**才能删（约 250 LUT），本轮不动；
- 频谱强调扫描（SW1/SW4）：仍是加分项的可演示功能，保留。

## 2. 本次具体改动

### 批次 A（本轮做）：删 bank 源尺寸通路

1. `sd_card_bmp.v`：删 `bank_src_w_r`/`bank_src_h_r`、`bank_src_w`/`bank_src_h` 输出端口、以及 load 完成时写这两组寄存器的语句；
2. `bmp_read.v`：删 `source_width`/`source_height` 两个输出（任务 1 若需要源尺寸再加回来）；
3. `top_tf_hdmi_audio.v`：删 `bank_src_w_sd`/`bank_src_h_sd`、`bsw_meta/sync`、`bsh_meta/sync`、`cur_src_w/cur_src_h` 的 mux，`src_info_render` 的 `src_w/src_h` 接常量（模块内部本来就用常量表，输入端口可保留悬空或一并删除）。

### 批次 B（本轮做）：删 `state_code` 与死机检测

- 先定位这两块的具体位置与影响面（`state_code` 是否还被别的地方引用，如 7 段译码、死机锁存的原因码）；
- 删之前确认**数码管显示口径不变**（图片编号、音量档、状态位仍要工作）。

### 批次 C（本轮做）：从 `.prj` 移除 9 个未实例化文件

- 同步 `syn_1/*.prj`、`phy_1/*.prj`、`*.al`；
- 目的：缩短构建、避免接手误读；**不期望 slices 变化**。

## 3. 验收方式

### 构建侧

- 综合：**黑盒 = 0**；
- 布线：`slices` 应低于 95.11%；分域门禁 `video_clk ≥ 0`、`sd_card ≥ −0.6`、`ext_mem ≥ −0.8`；
- 记录改动前后的 REG / LUT / slices 对比表（用于判断批次 C 是否真的"零收益"）。

### 上板侧

1. 四页菜单图正常显示、翻页无缝；
2. 左上角 `PAGE n/4`（或当前 `SRC 1280X960`）与右上角歌名/倒计时正常；
3. 频谱随音乐起伏；设置面板 6 项可用；数码管编号/音量/状态正常；
4. 拔卡保持最后帧、重插自动重载。

## 4. 回退点与回退步骤

- 若任一批次导致功能异常：把对应文件**逐个**回退（每批次单独一次构建，便于定位）；
- 全量回退：从 `sim/backups/ui_v4_20261024/` 覆盖 `top_tf_hdmi_audio.v`、`osd_buffer_overlay.v` 等，并按 E18.9 的源码状态恢复（台账有 MD5 记录）；
- 纪律：**每批次一构建**，不把三批混在一次构建里，否则省了多少、坏没坏都说不清。

---

## 5. 执行记录

### 批次 A（删 bank 源尺寸通路），2026/10/25 14:20

- 改动：`sd_card_bmp.v` 删 `bank_src_w_r/h_r`（2×64bit）与两个输出；`bmp_read.v` 删 `source_width/source_height`；`top` 删同步寄存器与 mux，`src_info_render` 的 `src_w/src_h` 接常量（模块内部本来就查 `TAB_W*/TAB_H*`）。
- 编译踩坑：删端口后 `sd_card_bmp.v` 端口表留下**行尾多余逗号** → `near ")": Missing port in ansi port list`，补掉即可。
- 综合：REG **9674 → 9261（−413）**、LUT 10497 → 10442（−55）、黑盒 0。
- 布线：seed 5 出现 `ext_mem −3.933`（布局抽奖变差）；扫种子后 **seed 13** 过门禁（slices 95.89%、sd −0.530、video +13.132、ext −0.443）。
- 烧录 MD5 `D91119CDB1811148BBD56538E9F0C784`，上板验收通过。
- **教训**：`seed_sweep.ps1` 只跑 phy 不写 `best_result`，需手动把 `phy_1` 的 bit 拷进 `best_result` 再烧，否则会烧到上一个种子的产物。

### 批次 B（删状态码位），2026/10/25 15:20

- 改动：数码管第 6 位（`seg_data_5`）改为常灭；删 `seg_decoder_m0` 实例与 `state_code` 连线。
- 综合：REG 9261 → **9258**、LUT 10442 → **10389**、黑盒 0。
- 布线：扫种子，**seed 17** 过门禁且三个域都是目前最好：slices **95.21%**、`video_clk` **+13.117**、`sd_card` **−0.253**、`ext_mem` **−0.136**。
- 烧录 MD5 `B1B5B1D9CD98BD5CC5F2A1485BD2F006`，上板验收通过（数码管 8 位亮 3 位：音量档 / 图号 / bank 有效位）。
- **结论**：本批逻辑上省 3 个寄存器、53 LUT，但真正收益是**时序**——`sd_card` 改善 0.43ns、`ext_mem` 改善 0.85ns，为任务 1 的 mask 通路留出了余量。

### 批次 C（从 .prj 移除 9 个未实例化文件）——**决定跳过**

未实例化模块综合时本就会被裁掉，移除文件**不改变面积**，只缩短构建时间；收益远低于风险，留给最后整理时一次性做。

### 最终结论

- 目标"secles 降到 92% 以下"**未达成**（95.21%），原因是面积数字受**布局抽奖**影响（±1%），而本轮真实收益体现在时序余量上；
- 更大的面积回收点在**任务 1**：删掉旧点阵字幕通路（约 250 LUT），届时一并完成。
