# Anlu 小步推进方案 E15（E14 上板测试后小修）

> **来源**：2026/10/20 第一轮功能测试（29 条）**全部通过**，用户提出 4 个改进方向，本次落地其中 2 个代码修复 + 1 个方案补记。
> **当前稳定点**：E14｜**预计产出**：E15
> **不做**：波形改进（待单独讨论）、左上 OSD 面板代码改动（只补方案）

---

## 1. 背景与目标

### 本轮要改的两处

1. **长按切歌只切一首**：现状按住不放会按 120ms 间隔连续切歌，改为**一次长按只切一首，无论按多久**。
2. **默认音量改为 0**：现状上电默认 `C`（12/15），改为 **0（完全静音）**，避免上电突然出声。

### 本轮只补文档、不改代码

3. **左上 OSD 面板不再常显，内容并入设置界面**：方案中缺这一条，补进 `项目方案.md` 的任务 13。

### 明确不做

- 不改底部音乐波形（V2-03 无 BUG，效果改进另行讨论）
- 不改 `video_osd_overlay.v` 的左上信息面板（等设置界面一起做）
- 不动任何与图象显示、转场、缩放相关的逻辑

---

## 2. 当前代码事实

### 2.1 长按切歌为什么会一直变

`key_longshort.v`（109 行）：

- 参数在 L14~20：`LONG_CYCLES`、`REPEAT_CYCLES`。
- 状态机三段：`S_IDLE` → `S_TIMING`（计时）→ `S_LONG`（长按保持）。
- **L92~101 的 `S_LONG` 分支**：每 `REPEAT_CYCLES - 1` 就 `long_repeat <= 1'b1` 再发一次脉冲——这就是"一直变"的根因。
- 进入 `S_LONG` 时（L80~86）已经立刻发过一次 `long_repeat`，所以重复脉冲是额外的。

`top_tf_hdmi_audio.v`：

- L971 / L975 两处例化 `key_longshort #(.CLOCK_MHZ(25), .LONG_CYCLES(15_000_000), .REPEAT_CYCLES(3_000_000))`。
  - `LONG_CYCLES` = 15,000,000 @25MHz = **600 ms**
  - `REPEAT_CYCLES` = 3,000,000 @25MHz = **120 ms**
- L973 / L977：`.long_repeat(k1_long_v)`、`.long_repeat(k2_long_v)`。
- L993~1002：`if (k2_long_v) ... 2'b10` / `else if (k1_long_v) ... 2'b01`——用 `long_repeat` 触发切歌命令，故每来一个重复脉冲就切一首。

**全工程仅这两处例化 `key_longshort`**，改动不会波及别处。

### 2.2 默认音量实际在顶层例化处

- `audio_volume_gain.v` L14：`parameter [3:0] DEFAULT_VOL = 4'd12`；L33 复位时 `vol <= DEFAULT_VOL`。
- **但顶层 L（例化处）把它覆盖了**：`audio_volume_gain #(.DEFAULT_VOL(4'd12)) u_vol_gain (...)`。
- 结论：**只改模块默认值不生效，必须改顶层例化值**；两处都改是为了一致性。
- 音量档 4 位，0=静音、15=最大（`gain_q15 = vol * 2184`，15 时为 32760≈0.99976）。

### 2.3 会受影响的既有测试

`Project/sim/tb_key_longshort.v`：

- 场景 2（L82~95）断言 `d_rep >= 4`，即**期望长按产生多个 repeat**。
- 本次行为改为单次后，该断言必须同步改为"恰好 1 个"，否则仿真会报 FAIL。

### 2.4 仿真环境现状

- `Project/sim/work_v209/list.f` 里的路径全是 `E:/Anlu/7_lab_ex_2026_nosoft/test/Project-10-12-22-39/...`，**该路径已不存在**（实测 `Test-Path` 为 False），清单已失效，需按当前 `D:\AAA_University\Anlu\Project\src` 重建。
- 本机可用 `vlog`（ModelSim，`D:\Modelsim\Install\win64\vlog.exe`）与 `iverilog`（`C:\iverilog\bin\iverilog.exe`）。按 `Anlu.md` 口径用 **vlog**。
- 厂商宏文件实测在 `D:\TD5.6.2\arch\eagle_macro.v`（`Anlu.md` 记的 `E:/Anlu/TD_6_2_1/...` 已失效，回填到台账）。
- 当前工程 `user_source` 下共 **64** 个 `.v` 文件。

---

## 3. 改动步骤

### 步骤 1：`key_longshort.v` 增加 REPEAT_ENABLE 参数

- 在参数表（L15~20）新增 `parameter integer REPEAT_ENABLE = 1`，默认 1 保持向后兼容。
- `S_LONG` 分支（L92~101）改为：`REPEAT_ENABLE == 0` 时不再发重复脉冲，仅保持 `long_active = 1` 直到松手。
- 不改 `S_TIMING`（短按判别）与进入长按时的那一次 `long_repeat`。

### 步骤 2：顶层两处例化传 0

- L971、L975 的 `key_longshort` 例化各加 `.REPEAT_ENABLE(0)`。
- 保留 `REPEAT_CYCLES(3_000_000)` 不变（参数存在但不生效，便于以后恢复）。

### 步骤 3：默认音量改 0

- `top_tf_hdmi_audio.v` 例化处：`.DEFAULT_VOL(4'd12)` → `.DEFAULT_VOL(4'd0)`。
- `audio_volume_gain.v` L14：`4'd12` → `4'd0`（保持模块默认与实例一致）。

### 步骤 4：更新 `tb_key_longshort.v`

- 场景 2 断言由 `d_rep >= 4` 改为 `d_rep === 1`（长按只发一次）。
- 注释同步说明新语义。

### 步骤 5：重建仿真清单

- 在 `Project/sim/` 下新建 `work_e15/`，生成指向 `D:\AAA_University\Anlu\Project\src` 的 `list.f`。
- 不删除旧 `work_v20x` 目录（历史留档）。

---

## 4. 验收方式

### 4.1 本地仿真（我执行）

1. `vlog` 编译 `key_longshort.v` + `ax_debounce.v` + `tb_key_longshort.v`，跑 `vsim -c`，要求输出 `KEY_LONGSHORT TEST PASS`。
2. 全量 `vlog` 64 个源文件（含 `+incdir` 到 `hdl_source`、`hdl_source/include`、`hdl_source/SD`），要求 **0 error**，warning 与基线一致。

### 4.2 用户 TD 与上板

1. 重新 `syn_1` / `phy_1` / bitstream。
2. 上板核对：
   - 音量模式长按 KEY4 不放 3 秒 → **只跳一首**，松手不再跳；再长按 KEY2 只上一首。
   - 上电后数码管第 5 位显示 `0`，**无声音**；按 KEY4 加音量后才出声。
   - 短按加减音量仍正常（一次一档）。
   - 其余功能无回归（切图、轮播、转场、缩放、状态栏、波形）。

### 4.3 需同步更新的文档

- `工程交互使用说明文档.md`：默认音量 `C`→`0`；删除"持续长按约 120ms 重复切歌"。
- `项目方案.md`：任务 13 增补"左上信息面板并入设置界面"；方案变更记录加一行。
- `项目进度.md`：登记第一轮测试全过、本次改动与 E15。

---

## 5. 回退点与风险

### 回退点

- 改动前稳定版：**E14**。若上板异常，撤销步骤 1~3 的 RTL 改动即回 E14。

### 风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| 默认音量 0 导致上电完全无声 | 演示时误以为音频坏了 | 使用说明显著标注"上电静音，需先加音量"；上板验收第 2 条专门检查 |
| 长按改为单次后，用户想连续切多首时不便 | 操作体验 | 需求方明确要求单次；如需连切，松手再按即可 |
| `REPEAT_ENABLE` 默认值 1，若别处复用仍会重复 | 未来误用 | 全工程仅这两处例化且都显式传 0 |
| tb 断言改动掩盖真实缺陷 | 误判通过 | 同时保留场景 1（短按恰好 1 次）与场景 2 的 `long_active` 检查 |

---

## 6. 任务过程记录

（执行中追加，历史不改写）

### 记录 1：方案建立（2026/10/20）

- 已完成第 2 节的代码核对，确认两处根因与 tb 影响面。
- 发现 `sim/work_v209/list.f` 指向的 E: 路径已失效、`Anlu.md` 记的 `eagle_macro.v` 路径也已失效，均需按实测路径更新。
- 经用户确认：长按采用方案 A（加 `REPEAT_ENABLE` 参数置 0）、默认音量改 0、左上 OSD 面板只补方案不改代码、第 5 条改进项暂缺。

### 记录 2：步骤 1~5 实施完成（2026/10/20）

**代码改动**

| 文件 | 改动 |
|---|---|
| `SD/key_longshort.v` | 参数表新增 `REPEAT_ENABLE = 1`（默认保持向后兼容）；`S_LONG` 分支改为 `REPEAT_ENABLE != 0` 时才计数并重复发 `long_repeat`；头部注释同步说明两种模式 |
| `top_tf_hdmi_audio.v` | 两处 `key_longshort` 例化各加 `.REPEAT_ENABLE(0)`；`audio_volume_gain` 例化 `.DEFAULT_VOL(4'd12)` → `(4'd0)` |
| `SD/audio_volume_gain.v` | `DEFAULT_VOL` 默认值 `4'd12` → `4'd0`；顺带修正头注释中"增减脉冲来自 long_repeat"的旧描述（实际来自 `short_pulse`，顶层接的是 `k*_short_v`） |
| `sim/tb_key_longshort.v` | DUT 加 `.REPEAT_ENABLE(0)`；场景 2 断言由 `d_rep >= 4` 改为 `d_rep != 1` 即报错；注释同步 |

**仿真环境重建**

- 旧 `sim/work_v209/list.f` 全部指向 `E:/Anlu/7_lab_ex_2026_nosoft/test/Project-10-12-22-39/...`，该路径实测已不存在，清单失效。
- 新建 `Project/sim/work_e15/list.f`，按当前 `D:\AAA_University\Anlu\Project\src` 路径生成，含 4 条 `+incdir`（td_project、hdl_source、include、SD）与 **61** 个源文件，与原清单数量一致。
- 排除 `hdl_source/test/` 与 `ip_source/`（同原清单口径）。
- 旧 `work_v20x` 目录保留未删。

**本地检查结果**

| 检查 | 结果 |
|---|---|
| 全量 `vlog`（61 文件） | 编译出 **65 个模块**，本次涉及的 `key_longshort`、`audio_volume_gain`、`sd_card_bmp`、`track_controller` 与顶层（模块名 `top`）**全部编译通过** |
| 编译错误 | 仅 **2 条**，均在厂商加密文件：`sdr_init_ref.enc.v(213) Illegal concatenation of an unsized constant`、`sdr_wrrd.enc.v(83) in protected region`。属 ModelSim 无法解析 protected region 的既有局限，与本次改动无关 |
| `tb_key_longshort` 仿真 | **PASS**：`S1 short: short=1 repeat=0 saw_long=0`；`S2 long: d_short=0 d_repeat=1 saw_long=1`——长按由原来的"≥4 次重复"变为**恰好 1 次**，短按仍恰好 1 次、长按不再误发短按 |

**尚未执行**（按 `Anlu.md` 由用户完成）：TD `syn_1` / `phy_1` / bitstream 与上板验收（第 4.2 节清单）。

