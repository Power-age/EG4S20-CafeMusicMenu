# Anlu 小步推进方案：冷上电清屏不干净（条纹）修复

> **来源**：2026/10/20 用户上板发现——缩放图（PIC3 小图放大 / PIC4 大图缩小）未覆盖的黑边区域出现稳定白色条纹；**按 KEY1 软复位后条纹消失**；PIC1（640×480 满屏）显示正常。
> **当前稳定点**：E15 + 一期约束 + 二期 A/B/D/C1（上板功能正常，Setup 374 EP / −1.287）

---

## 1. 背景与目标

### 现象与已排除项

| 观察 | 结论 |
|---|---|
| PIC1 满屏显示正常，条纹消失 | 显示管线与满帧写入通路正常 |
| 条纹只出现在缩放图未覆盖的区域 | 与内存清屏（黑边来源）相关 |
| **KEY1 软复位后条纹消失** | **冷上电初始化窗口的问题**，非稳态逻辑错误 |

已用仿真排除（结果均为 PASS）：

| 测试 | 覆盖 | 结果 |
|---|---|---|
| `tb_frame_clear_sweep` | 8×4 整帧写入地址覆盖不重不漏 | PASS |
| `tb_frame_geometry` | **640×480 / BURST 128 / ADDR 21 真实几何逐点校验 307200 点** | PASS（0 错） |
| `tb_clear_bank` | 清 bank 状态机（含 ack 同步后） | PASS |
| `tb_chain_shim` | 簇链寻址（含 C1 改动） | PASS |

即 `frame_fifo_write` 地址映射（含 A/D 改动）、清 bank 状态机、簇寻址都在仿真中正确。

### 根因判断

`top_tf_hdmi_audio.v` L275：

```verilog
assign rst_all = ~rst_n | ~audio_pll_lock;
```

**只等音频 PLL 锁定**。`sys_pll`（产出 `sd_card_clk` 100MHz、`ext_mem_clk` 125MHz）与 `video_pll` 的 lock 状态完全没有参与复位——两个 PLL 包装文件里都是 `.extlock(open)`，锁信号被丢弃。

冷上电时 `rst_n` 释放、音频 PLL 先锁定，`rst_all` 随即解除，此时 sys/video PLL 可能尚未稳定，系统在未稳时钟下跑初始化，导致首次清 bank 不完整 —— 缩放图黑边露出非零内存内容，表现为稳定白条纹。KEY1 复位时三个 PLL 早已锁定，复位窗口干净，故条纹消失。

**这是长期存在的潜在竞态**，二期 A/B/D/C1 增加了流水寄存器与同步器，改变冷上电瞬间的时序余量把它踩出来了，不是某一步逻辑写错。

### 本次做

把 `sys_pll` 与 `video_pll` 的 lock 引出并纳入 `rst_all`，使冷上电与软复位行为一致。

### 本次不做

- 不改清 bank 状态机、不改 `frame_fifo_write`、不动二期时序改动。
- 不加额外的复位去抖计数器（音频 PLL 一直直接用 `extlock`，说明该信号可靠，先保持一致）。

---

## 2. 当前代码事实

| 文件 | 现状 |
|---|---|
| `IP/sys_pll.v` | 端口仅 `refclk/reset/clk0_out/clk1_out/clk2_out`；L77 为 `.extlock(open)` |
| `IP/video_pll.v` | 端口仅 `refclk/reset/clk0_out/clk1_out`；L70 为 `.extlock(open)` |
| `top_tf_hdmi_audio.v` | L237 `wire audio_pll_lock;`；L273 `wire rst_all;`；L275 `assign rst_all = ~rst_n | ~audio_pll_lock;`；sys_pll/video_pll 例化在 L860~880 附近，`.reset(1'b0)` |
| 参考 | 音频 PLL 例化处 L598 已有 `.extlock(audio_pll_lock)`，即同类信号已被验证可用 |

---

## 3. 改动步骤

### 步骤 1：`IP/sys_pll.v` 引出 lock

- 端口列表 `clk2_out` 后加 `lock_out`，并加 `output lock_out;` 声明。
- `.extlock(open)` → `.extlock(lock_out)`。

### 步骤 2：`IP/video_pll.v` 引出 lock

- 端口列表 `clk1_out` 后加 `lock_out`，并加 `output lock_out;`。
- 该文件的 `.extlock(open)` 同样改为 `.extlock(lock_out)`。

### 步骤 3：顶层纳入复位

- 新增 `wire sys_pll_lock;`、`wire video_pll_lock;`
- 两个 PLL 例化各加 `.lock_out(...)` 连接
- `assign rst_all = ~rst_n | ~audio_pll_lock | ~sys_pll_lock | ~video_pll_lock;`

### 步骤 4：本地检查 + TD + 冷上电验证

---

## 4. 验收方式

| 检查 | 判据 |
|---|---|
| 全量 `vlog` | 无新增错误（新增 2 个输出端口，顶层连接一致） |
| TD `syn_1`+`phy_1` | 构建通过；slices/时序不回退（应几乎不变） |
| **冷上电**（拔电重插，非 KEY1） | PIC3 / PIC4 的黑边**纯黑无条纹**；PIC1/PIC2 正常 |
| 冷上电后功能 | 数码管第 7 位 1→3→7→F、四图可切、音乐正常 |

> 必须**冷上电**验证：软复位无法复现该问题。

---

## 5. 回退点与风险

**回退点**：改前即当前 A/B/D/C1 状态（上板功能正常，仅冷上电黑边有瑕疵）。

| 风险 | 影响 | 缓解 |
|---|---|---|
| `IP/*_pll.v` 是 TD 生成文件，重新生成 IP 会覆盖此改动 | 修复丢失、条纹复发 | 在 `项目进度.md` 遗留条目里记录"重新生成 IP 后须重新引出 extlock" |
| `extlock` 抖动导致 `rst_all` 反复复位 | 系统起不来 | 音频 PLL 一直直接使用 `extlock` 且工作正常，同源同型号；若异常则加去抖计数器 |
| 两个 PLL 的 lock 迟迟不来 | 一直复位、黑屏 | 冷上电验证第一眼即可发现；可退回只保留 sys_pll |

---

## 6. 任务过程记录

（执行中追加）

### 记录 1：方案建立（2026/10/20）

- 通过用户"KEY1 复位后条纹消失"定位到冷上电初始化窗口。
- 以 `tb_frame_clear_sweep`、`tb_frame_geometry`（真实 640×480 逐点）、`tb_clear_bank`、`tb_chain_shim` 四项仿真排除地址映射与状态机，确认问题不在二期逻辑改动。
- 查明 `rst_all` 仅依赖音频 PLL lock，sys/video PLL 的 `extlock` 未引出。

### 记录 2：改动完成与构建（2026/10/20 22:22）

**改动文件（3 个）**

| 文件 | 改动 |
|---|---|
| `IP/sys_pll.v` | 端口新增 `lock_out`（L30 列表 + L38 声明）；`.extlock(open)` → `.extlock(lock_out)`（L79） |
| `IP/video_pll.v` | 端口新增 `lock_out`（L28 + L35）；`.extlock(open)` → `.extlock(lock_out)`（L72） |
| `top_tf_hdmi_audio.v` | 新增 `wire sys_pll_lock` / `video_pll_lock`（L238~239）；两个 PLL 例化加 `.lock_out(...)`（L586、L594）；`rst_all` 改为 `~rst_n \| ~audio_pll_lock \| ~sys_pll_lock \| ~video_pll_lock`（L277） |

**写法已核对**：TD 自己生成的音频 PLL IP `al_ip/PLL_HDMI_AUDIO.v` 就是 `output extlock` + `.extlock(extlock)`（L35、L79），本次改动与之同构，不是自创接法。

**构建**：全量 `vlog` 仅 2 条既有厂商加密文件错误；`syn_1` 2m43s、`phy_1` 6m17s，均 exit=0；bitstream 已同步 `best_result`（MD5 一致）。

**时序（附带记录，非本次目标）**：Setup WNS −1.287 → −1.731、违例端点 374 → 364、Hold 5 条 −0.011、slices 9009 → 9061（92.46%）。属拥塞下的布局重排，量级正常。

**待验证（必须冷上电）**：拔电重插，看 PIC3/PIC4 黑边是否纯黑；KEY1 软复位验证不了该问题。

### 记录 3：冷上电验证通过（2026/10/20）

用户拔电重插验证：**条纹消失，缩放图黑边纯黑，显示正常**。修复成立，本方案可归档。

结论沉淀：`rst_all` 必须覆盖全部三个 PLL 的 lock（音频 / sys / video）。此前只等音频 PLL 是长期隐患，冷上电时偶尔会让首次清 bank 不完整。
