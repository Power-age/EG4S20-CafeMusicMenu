# Anlu 小步推进方案 V2-05：字体 ROM 与 OSD Buffer 存储基础设施

## 1. 背景与目标

对应 `Project/doc/项目方案.md` 的 V2-05：建立 ASCII 32~127 的 8×8 字体读取口和 256×16×2bit 的 OSD 像素存储，分别以 BRAM9K 实现。V2-04 双曲目主路径上板获用户确认，完整边界及 `phy_1` 证据待补；E10 为完整回退证据基线。

本步不改现有 OSD、波形和 HDMI 输出，不实现 V2-06 渲染器、V2-07 视频叠加，不修改用户操作，也不写代码注释。V2 原方案的“256×16 的每个像素对应屏幕 8×8”与“屏幕上 256×128 区域”水平尺度不一致；本步只冻结逻辑存储地址，显示坐标映射留后续任务解决。

## 2. 当前代码事实

- `Project/src/user_source/hdl_source/top_tf_hdmi_audio.v` 第 695~727 行：video_clk 管线先 `waveform_render`，再 `video_osd_overlay` 输出最终 RGB；本步只在同域旁路例化新存储，不修改这些连线。
- `Project/src/user_source/hdl_source/video_osd_overlay.v` 第 176 行起的 `glyph_row` 是旧 5×7 字模，字符覆盖不完整，不能直接充当完整 96 字符的 8×8 ROM。
- `Project/src/user_source/hdl_source/SD/track_list.v` 第 35~60 行：`TRACK_LIST_SIM` 模型与显式 `EG_LOGIC_BRAM`；`Project/src/user_source/hdl_source/waveform_ram.v` 第 147~196 行：仿真数组与显式双口 BRAM 的既有写法。
- V2-04 最终 `syn_1` 记录为 BRAM9K=34、DSP=13、LUT=14625；该记录不能替代新源码的真实资源报告。现有 OSD 消费口不连接新存储，TD 可能优化掉旁路实例。

## 3. 改动步骤

1. 新增 `Project/src/user_source/hdl_source/font_rom.v` 与 `font_data.mem`。字符 7bit，行 3bit，地址 `{ascii-32,row}` 共 768×8bit；0~31 返回 0（无下溢），127 全部 8 行有效。用 8×8 点阵覆盖 96 个 ASCII 位置，旧 5×7 字模仅作参考；`.mem` 文件须与 TD/ModelSim 工作目录配置保持一致。读同步一拍，`rd_valid` 与输出数据同步。
2. 新增 `Project/src/user_source/hdl_source/osd_buffer.v`：12bit 地址由 `{y[3:0],x[7:0]}` 拼接，逻辑 4096×2bit；使用 `EG_LOGIC_BRAM` 的双口模式分别同步写/同步读，独立仿真模型，输出 `rd_valid` 对齐数据。未写单元的值不保证；复位不清 RAM 内容；同地址同时读写不保证，V2-06 消隐调度规避。
3. 在顶层 video_clk 域无写入、读使能关闭地例化，预留 V2-06/07 接口；不改变任何现有视频或音频路径。新 Verilog 源由用户在 TD GUI Add Source；不要手改会被 TD 覆盖的 `.al`。
4. 新增 `Project/sim/tb_font_rom.v`、`tb_osd_buffer.v`：验证字符范围、A 的 8 行、空格、地址边界、四种像素类型和同步延迟。仅更新本执行方案与 `Project/doc/项目进度.md`；纯内部基础设施不触发使用说明变化。

## 4. 验收方式

- ModelSim 单模块仿真：对字体空间 0、31、32、65、126、127 边界和 A 的 8 行；对 Buffer 地址 0/255/256/4095、写后读、四种 2bit 值、rd_valid 一拍。未写数据不参与比对，避免仿真与硬件未初始化内容口径冲突。
- 采用工程 ModelSim `vlog` 编译新模块与测试台；顶层包含新增模块的编译、必要时以临时 stub 完整展开，检查无新增隐式线网/锁存/黑盒。若 `.mem` 读取路径或原语初始化不适配 TD，先纠正路径及实现，不退化成大规模 LUT。
- 用户在 TD GUI 加入两份 RTL 及字体数据文件，执行 `syn_1`，检查是否各落 1 个 BRAM9K、DSP 保持 13、LUT 无异常、LATCH=0、无新增黑盒。以 V2-04 实报 BRAM34 为基线，预期消费端存在时为36；旁路未连接时可能被裁剪，需如实记录且不能当作最终资源验收。TD `phy_1`、bitstream 与上板由用户执行，本步无可见变化不要求烧录。

## 5. 回退点与风险

回退点为现有 V2-04 双曲目主路径上板获用户确认的工程，完整边界与时序指标未获证据；E10 仍为有完整回退记录的硬件稳定基线。新模块发生资源或编译异常时撤掉顶层旁路实例及两模块/字模文件，保留已有 OSD、SD/SDRAM/HDMI/音频。风险包括字体 ROM 数据文件路径、BRAM 初始化工具支持、未消费被综合裁剪、双口同址碰撞与未来显示坐标尺度不一致；逐一通过仿真和用户 TD 报告核对，不混入 V2-06/07 行为。

## 6. 任务过程记录

- 2026/10/12：用户确认 V2-04 双曲目主路径上板测试通过并要求继续推进；V2-04 方案已归档，完整边界仍待补证。本方案建立后才开始 V2-05 实现。
- 2026/10/12：新增 `font_rom.v`、`osd_buffer.v` 和两个单模块测试台；`top_tf_hdmi_audio.v` 在现有 waveform→OSD 链外增加禁用读写的旁路实例，用户可见行为不变。字体数据以 ASCII 原码为地址高 7 位、行号为低 3 位，0~31 补零，实际为 1024×8bit；32~127 共 96 字符，空格为空、DEL 为可见占位符。使用 Pillow 内置 Aileron Regular 的 7px 字形栅格化制作数据，`font_data.mem` 供 ModelSim，内容等价的 `font_data.mif` 供原语 `INIT_FILE`（沿用工程音频 ROM 的相对路径写法），不把 `.mem` 直接用于 TD 原语。数据文件多于方案中的 768 字节，是为了免去 ASCII 减 32 的组合减法及处理下溢；两种初始化文件 1024 项逐项一致。同步输出一拍、复位仅清有效标志；Buffer 未写地址及同址同时读写不保证。
- 2026/10/12：ModelSim 10.1c 的 `tb_font_rom`（扫描 0~127 全部八行、A 八行、DEL、复位）与 `tb_osd_buffer`（地址 0/255/256/4095、四种像素值、覆写、读有效和复位）均 PASS；新模块及顶层经 `vlog` 语法编译，新增 RTL 严格语法检查无警告。尝试完整顶层展开时，已有 `sdr_as_ram.enc.v` 加密区在当前 ModelSim 报 `in protected region`，无法据此声称顶层完全展开；此故障不出在新增模块。厂商 `eagle_macro.v` 仅有原语声明而无行为，未能在本地模拟真实 MIF 初始化或测量 BRAM/LUT、LATCH。TD `syn_1` 尚未运行，资源与 MIF 初始化仍须用户在 TD GUI 验证；旁路实例可能被裁剪，因此 V2-05 保留执行中，不归档、不宣称资源判据通过。
- 2026/10/12：用户已运行 TD `syn_1`。检查本机 `Project/src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/syn_1/run.log`：成功分析 50 个源文件并展开 `font_rom`、`osd_buffer`，字体 BRAM 的 `INIT_FILE` 参数指向 `font_data.mif`；最终资源 LUT 14625、REG 8330、BRAM9K 34、DSP 13、LATCH 0，均与 V2-04 基线相同。两旁路实例无有效读写且输出未消费，未被保留为额外 BRAM；报告中没有 MIF 找不到的提示，但目前既没有保留字体 BRAM，也没有可观察的字体输出，故不能证明初始化已写入硬件。`syn_1` 日志显示 setup WNS -7288ps、hold WNS +471ps（仅综合估计，不是 `phy_1`）。冻结的各占一个 BRAM9K 判据未达成，继续等待真正消费端接入后的资源及初始化验证，方案暂不归档。
