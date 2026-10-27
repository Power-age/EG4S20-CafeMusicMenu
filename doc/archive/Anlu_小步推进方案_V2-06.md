# Anlu 小步推进方案 V2-06：消隐期 OSD 渲染状态机 + 行级脏标记

## 1. 背景与目标

对应 `Project/doc/项目方案.md` V2-06（批内"任务 6：消隐期渲染状态机 + 行级脏标记"）。V2-05 已建好两块存储：`font_rom.v`（96 个 ASCII 的 8×8 字模，同步读一拍）与 `osd_buffer.v`（256×16×2bit 双口 BRAM），但在顶层是旁路死接（`rd_en=0 / wr_en=0`），尚未被消费，syn_1 报告 BRAM 仍为 34、存储有被综合裁掉的风险。

本步目标：新增 `osd_renderer.v` 渲染引擎，把"字符 ASCII + 坐标 + 像素类型"翻译成 8×8 像素写入 `osd_buffer`，并在垂直消隐期调度、维护行级脏标记。本步**只写不读**：osd_buffer 的视频读口仍不接视频管线（读口叠加是 V2-07 的事），因此上板视觉与 E11 完全一致；本步以 ModelSim 仿真为主验收，TD 侧验证存储被真实保留（BRAM 34→36）。

不改现有 OSD、波形、SD/SDRAM/HDMI/音频路径，不改用户操作，不写代码注释。

## 2. 当前代码事实（已读）

- `font_rom.v` 接口：`clk, rst, rd_en, ascii[6:0], row[2:0] → rd_data[7:0], rd_valid`；同步读一拍（`rd_valid <= rd_en`）；`ascii<32` 读零；地址 `{ascii,row}`，96 字模已由 V2-05 用 Pillow Aileron 7px 栅格化生成（`font_data.mem/mif`）。
- `osd_buffer.v` 接口：写口 `wr_en, wr_x[7:0], wr_y[3:0], wr_data[1:0]`（地址 `{wr_y,wr_x}`，PDPW 模式）；读口 `rd_en, rd_x[7:0], rd_y[3:0] → rd_data[1:0], rd_valid`；未写单元值不保证、同址同时读写不保证。
- top `top_tf_hdmi_audio.v` 第 712~722 行：`u_font_rom` 与 `u_osd_buffer` 旁路死接；video 管线在 video_clk(25MHz)/rst_all 域，已有 `vs`、`de`、`video_x_cnt[9:0]`、`video_y_cnt`（`video_delay` 输出），`waveform_render` 已消费 `vs/de` 并输出 `wave_vs/wave_de`。
- V2-05 已声明的待决项：buffer 像素到屏幕的坐标映射（1:1 还是 1:8）留 V2-07；本步只按 buffer 自身坐标（x=0~255 列、y=0~15 行）写。

## 3. 渲染约定（本步冻结）

- **字符画布**：一个字符 8×8 像素，在 buffer 中占 `x = char_x*8 .. +7`、`y = char_y .. +7`；`char_x` 范围 0~31，`char_y` 对齐到 8 的整数倍（0 或 8，buffer 只有 16 行）。
- **字模位序**：`font_rom.rd_data[7:0]` 的 **bit7 = 该字符最左像素（x 偏移 0），bit0 = 最右（x 偏移 7）**；写第 c 列时取 `glyph[7-c]`。该约定在 `tb_osd_renderer` 里以 'A' 的已知点阵复核。
- **像素类型 2bit**：00=透明、01=面板底、10=文字、11=高亮（含义由 V2-07 alpha 混合解释，本步只透传）。
- **消隐期窗口**：检测 `vs` 上升沿（`vs && !vs_prev`）后启动渲染；活动区（de=1）期间不写 buffer。VS 消隐约 1.2ms / 25MHz ≈ 30000 拍，单字符约 8 行×(1 读+8 写)≈72 拍，消隐期可轻松画完整一行 32 字符。

## 4. 改动步骤

1. 新增 `hdl_source/osd_renderer.v`：
   - 端口：`clk, rst, vs`；字符请求 `req_valid/req_ready, req_ascii[6:0], req_x[7:0], req_y[3:0], req_type[1:0]`；font_rom 出口 `font_rd_en/font_ascii/font_row` 与入口 `font_rd_data/font_rd_valid`；buffer 写口 `buf_wr_en/wr_x/wr_y/wr_data`；调试输出 `busy`。
   - 状态机：`IDLE → 等 vs 上升沿 → 从请求接口取一个字符（反压 ready）→ 对 row=0..7：发 font 读（rd_en 一拍）→ 等 rd_valid → 拿到 glyph → 逐列 c=0..7 写 buffer（wr_y=req_y+row, wr_x=req_x*8+c, wr_data=glyph[7-c]）→ 回 IDLE 取下一个请求；请求空则等到下一帧`。
   - 行级脏标记：内部 `dirty_row[15:0]`，每画完一个字符把它所在 `req_y` 对应的 buffer 行（按 8 行一组换算）置位；对外提供 `dirty_row` 可读（V2-08/10 将用它做"只重绘变化行"）。本步不引入复杂队列，请求由上游逐拍给出。
2. top 接线（替换第 712~722 行死接）：
   - `u_font_rom` 的 `rd_en/ascii/row` 改接 `osd_renderer` 的 font 出口，`rd_data/rd_valid` 接回；
   - `u_osd_buffer` 的写口改接 `osd_renderer` 的 `buf_wr_*`；读口仍 `rd_en=0`（V2-07 再接）；
   - 新增 `u_osd_renderer`；其字符请求由一个最小"上电自检源"驱动：上电后第一帧 vs 时把固定串 `"ANLU6"`（5 字符，放 y=0 行、字符列 0~4，像素类型 10）逐字符 push 进去，之后请求恒 0。目的是让 buffer 写口在 syn_1 期间真实活动、两块 BRAM 不被裁掉；该测试串在 V2-07 接读口时会自然成为首个可视验收图案。
3. 新增 `sim/tb_osd_renderer.v`：
   - 用 `FONT_ROM_SIM`/`OSD_BUFFER_SIM` 宏实例化 font_rom、osd_buffer 与 osd_renderer；
   - 用例：①'@'位置 (x=2,y=0) 写一个字符，逐地址比对 buffer 像素与已知点阵；②连续写 "ANLU" 多字符不重叠不丢；③在活动区（de=1 期间）发请求不被绘制、vs 后才画；④dirty_row 置位正确；⑤32 字符连续请求在一个消隐窗口内画完且无超时。
4. 仅更新本方案件与 `Project/doc/项目进度.md`；本步上板无可见变化，不要求烧录。

## 5. 验收方式

- ModelSim 10.1c：`tb_osd_renderer` 全部用例 PASS，打印 `OSD_RENDERER PASS`。
- vlog 编译新模块 + 顶层无错、无新增隐式线网/锁存/黑盒。
- 用户在 TD GUI Add 新 `osd_renderer.v`，跑 `syn_1`：核对 BRAM9K 由 34 增至 36（font_rom 与 osd_buffer 各 1 块真实保留）、LATCH=0、DSP 仍 13、无字体 MIF 缺失报错；TD `phy_1`/bitstream 与上板由用户执行（上板视觉应与 E11 一致）。

## 6. 回退点与风险

- 回退点：E11（V2-03/V2-04 已上板稳定）。若 osd_renderer 异常，撤掉顶层 osd_renderer 例化、把 font_rom/osd_buffer 恢复为第 712~722 行死接即可回到 E11。
- 风险：①字模 bit 方向与 tb 预期不一致——用 'A' 已知点阵复核；②消隐窗口预算不足——单字符约 72 拍、一行 32 字符约 2300 拍，远小于消隐 30000 拍，留足余量；③buffer 仍被裁——靠上电自检串保证写口活动；④V2-05 遗留的 buffer 坐标映射矛盾本步不解决，留给 V2-07。

## 7. 任务过程记录

- 2026/10/15：本方案建立，待用户确认后实现。
- 2026/10/15：用户确认方案。新增 `hdl_source/osd_renderer.v`、`sim/tb_osd_renderer.v`；改 `top_tf_hdmi_audio.v`：旁路的 font_rom/osd_buffer 改接 renderer，新增上电自检源（首帧写 ANLU6）。
- 2026/10/15：ModelSim 10.5 独立库 `sim/work_v206` 编译仿真。首次仿真用例 5 出现"偶数列通过、奇数列读到未写入"的问题，定位为**测试台** valid/ready 零延迟握手竞争（negedge 置位后同时间步读组合 ready，读旧值，DUT 已自行取走而 testbench 仍等待，造成重复取走），非 RTL 缺陷；改测试台在置位后 `#1` 再采样即修正。同时把 RTL 的 font 读口由寄存输出改为组合输出（`font_rd_en` 仅在 S_READ 且非活动区），消除每行额外 1 拍等待，单字符由 89 拍收紧到 80 拍。
- 2026/10/15：`tb_osd_renderer` 全部用例 **PASS**（单字符像素、连续多字符、活动区/无新 vs 拒绝、dirty 行、复位；32 字符持续流 2592 周期、32 次 ready 无丢失）。生产 RTL 58 文件 `vlog -f` 全量编译 **0 错误**，仅加密 IP 的 `<protected>` warning 与既有 `SD/sdram.v` 重名 warning，新增/改动文件无新警告。
- 2026/10/15：待用户在 TD GUI Add Source `osd_renderer.v` 并跑 `syn_1`，核对 BRAM9K 34→36、LATCH=0、DSP=13、无 MIF 缺失；上板视觉预期与 E11 一致。TD 资源与上板证据未回，本步暂不归档、不升稳定点。
- 2026/10/15：用户首次 `syn_1` + 上板，现象与 E11 一致（正常），但 **BRAM9K 仍为 34、DSP 13**。查 `syn_1/run.log`：三模块均被分析并展开，渲染器状态机被识别为 one-hot FSM，但最终 `SYN-1023` 只推断 3 块 Logic BRAM（帧读写两块 + 音频一块），两块 OSD 存储原语被死代码优化删除。根因：两块 EG_LOGIC_BRAM 的 `FORCE_KEEP("OFF")`，而 V2-06 只有写口、osd_buffer 读口悬空（V2-07 才接），数据无外部输出，综合判整条链无用而删除。经用户确认，将 `font_rom.v`、`osd_buffer.v` 的原语参数改为 **`FORCE_KEEP("ON")`**（与工程内 `track_list.v` 保留 BRAM 的写法一致），强制保留两块 BRAM（font_rom 1024×8、osd_buffer 4096×2 各 8192bit，各占 1 个 BRAM9K），并连带保住渲染器写入链；无临时飞线、V2-07 接读口后无需回退。待用户重跑 `syn_1` 复核 BRAM9K 34→36。
- 2026/10/15：用户重跑 `syn_1`/`phy_1` 并上板，**通过**。`syn_1`：BRAM9K **36**（font_rom、osd_buffer 各 1 块，MIF 正常加载）、LATCH 0、DSP 13、LUT 14722、REG 8376。`phy_1` route QoR：LUT 15101/19600、REG 8498、BRAM 36、DSP 13；**Setup WNS −6699ps 与 E11 完全相同**（125MHz SDRAM 既有遗留）、**Hold WNS +11ps、0 个 hold 违例端点**（布局阶段一度 −11ps，布线后 "All hold violations are fixed"）。上板现象与 E11 一致（OSD 读口未接，`ANLU6` 不可见，符合预期）。V2-06 完成，方案件归档；OSD 读口叠加进入 V2-07。
