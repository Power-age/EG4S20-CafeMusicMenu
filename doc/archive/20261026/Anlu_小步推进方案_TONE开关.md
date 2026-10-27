# 小步推进方案：TONE 开关 + 测试音朴素频谱（任务 3+4 合并）

## 1. 背景与目标

`项目方案.md` §7 任务 3（测试音频谱正常化）与任务 4（`TONE` 开关）本质是同一件事：让"无卡/演示时"的内置测试音既能出声、也能驱动频谱，并且频谱在测试音模式下不叠加"强调峰扫过"。

**目标（单一）**：设置面板新增第 7 项 `TONE`（ON/OFF），
- `TONE=ON` → 音频 mux 强制选内置测试音（即使有 WAV 在播），频谱走朴素振幅（`emph=0`）；
- `TONE=OFF` → 恢复原行为（有 WAV 选 WAV，否则测试音；强调峰按 SW1/SW4 生效）。

**本次不做**：
- 不改测试音的**生成方式**（仍用 `hdmi_audio_tone_i2s_64fs` + `I2S_receiver` 回环，方案里提到的 DDS 直出留作后续，属纯内部质量项）；
- 不改右上角歌名（`status_bar_render` 的歌名来自 BRAM 里的名字表，显示 `TEST TONE` 需要重出该 MIF，另列后续）；
- 不动倒计时逻辑（TONE 下倒计时仍按当前曲目走）。

## 2. 当前代码事实（已核）

| 位置 | 现状 |
|---|---|
| `top` 第 1249~1260 行 | 音源 mux：`hdmi_audio_left = wav_play_v2 ? wav_pcm24 : audio_left_data`（有 WAV 选 WAV，否则测试音） |
| `top` 第 1330~1339 行 | `audio_volume_gain`：输入即 mux 之后 |
| `top` 第 1341~1353 行 | `waveform_data` 的 `sample_left/right` 取 `vol_audio_l/r`（**已在 mux 之后**） |
| `top` 第 903~911 行 | `spectrum_engine.sample_r = vol_audio_r`（mux→音量之后），故"取样点"已正确 |
| `top` 第 894~901 行 | `spec_emph_meta <= {~sw_con0, ~sw_transition}`，与音源无关 → 测试音也叠强调峰（本任务要修的点） |
| `menu_controller.v` | 6 行（`sel_row` 0~5），行内 `minus/plus` 的 case 在 214/225 行；循环边界在 197/200 行 |
| `menu_renderer.v` | 名称表 `name_char` 第 48~57 行（line 0=SETTINGS，1~6=六项）；数值表 `val_char` 第 71~122 行 |
| 面板几何 | `req_y = row*8 + 8`，row 0~7；面板高 144px，容得下第 8 行 |

## 3. 改动步骤

1. **`menu_controller.v`**：新增 `o_tone` 输出与 `p_tone`（默认 0）；`param_now` 带上 `p_tone`；行循环上限 `3'd5`→`3'd6`；两个 case 增 `3'd6: p_tone <= ~p_tone;`。
2. **`menu_renderer.v`**：新增 `p_tone` 输入；名称行 `3'd7: "TONE           "`；数值行 `3'd7` 显示 `ON`/`OFF`（槽位同 AUTO 写法）。
3. **`top`**：
   - `wire m_tone`，接 `menu_controller.o_tone` 与 `menu_renderer.p_tone`；
   - 音源 mux 改 `(wav_play_v2 && !m_tone) ? wav_pcm24 : audio_left_data`（右声道同）；
   - 强调峰改 `spec_emph_meta <= (m_tone || !wav_play_v2) ? 2'd0 : {~sw_con0, ~sw_transition}`。
4. **本地仿真**：`tb_menu_renderer` 更新（第 7 行文本/数值）+ 编译检查；无音频专用 tb，音频路径靠"mux 表达式"阅读核对 + 上板试听。

## 4. 验收方式

**我这边**：`vlog` 全量编译通过；`tb_menu_renderer` 过（TONE 行显示 `ON`/`OFF`）；构建三门禁通过并记录分域时序。

**用户上板清单**：
1. KEY3 开面板 → 面板多出第 7 行 `TONE`，KEY2/KEY4 能选中，单击 KEY3 进入编辑，KEY4 切 `ON`/`OFF`；
2. `TONE=ON` + 有卡在播 → 听到的是**测试音**（单一音调），不是歌曲；频谱变成**单根/少数柱**的朴素形态，不再有"扫过的强调峰"；
3. `TONE=OFF` → 恢复歌曲与 SW1/SW4 的强调档位效果；
4. 面板关闭后设置保持；按键切图、放大、翻页均不受影响。

## 5. 回退点与风险

- 回退点：E19.9，MD5 `A09F618864A0E945A16990F4D32B85EE`（`best_result` 当前即此版本）。
- 风险：菜单从 6 项变 7 项，面板高度/边界需上板确认；`p_tone` 上电默认 0，不影响现有演示；音频 mux 增加一个与门，面积可忽略。

## 6. 任务过程记录

（执行中追加）

- 2026/10/26 01:19 完成并烧录：menu_controller/menu_renderer/top 三处改动落地，	b_menu_renderer 过，构建三门禁过；MD5 A9C50A96CE0D040831F15F1848BE369A，slices 97.27%、ext_mem −0.609、sd −1.523。未做：DDS 直出、右上角 TEST TONE 标题（歌名 BRAM 需重出 MIF）。
