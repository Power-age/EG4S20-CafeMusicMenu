# Anlu 小步推进方案 V2-01：波形数据通路

## 1. 背景与目标

本任务对应 `Project/doc/项目方案.md` 的 V2-01，承接旧 V1-24“音频波形/峰值条”的数据基础部分。当前上板稳定点为 E10。

本次单一目标是从 HDMI 实际输出使用的音量增益后左右声道 PCM 中，生成连续的 640 点 8bit 波形幅值数据，并写入双口 BRAM，为 V2-02 波形渲染提供稳定接口。

本次只做数据采集、包络、窗口峰值、近似对数压缩和缓存，不做以下内容：

- 不做屏幕波形绘制、渐变色、峰值保持线；
- 不做 60fps 帧同步、双缓冲或帧间平滑；
- 不做状态栏融合和 OSD Buffer 重构；
- 不做多曲目播放；
- 不修改 WAV 播放器、数字音量、HDMI 音频发送、现有音频电平条；
- 不修改视频、OSD、转场、SDRAM、SD/FAT32 或约束；
- 不处理残留轻微沙声和既有 setup 违例；
- 不新增代码注释；
- 不由本轮执行 TD `syn_1`、`phy_1` 或 bitstream。

V2-01 以模块仿真、完整顶层编译、TD 源文件登记和用户综合检查作为独立完成判据。屏幕波形与音乐同步的可视上板验收归 V2-02；V2-01 完成后 E10 仍是当前上板稳定点。

## 2. 当前代码事实

### 2.1 最终音频采样点

实际工程为 `Project/src`。顶层文件 `Project/src/user_source/hdl_source/top_tf_hdmi_audio.v` 中：

- 唯一锚点 `I2S_receiver u_I2S_receiver`：以 `video_clk` 为时钟，输出 `audio_valid`、`audio_left_data`、`audio_right_data`；
- 唯一锚点 `assign wav_pcm24`：WAV 16bit 样本扩展为 24bit，并与测试音形成 `hdmi_audio_left`、`hdmi_audio_right`；
- 唯一锚点 `audio_volume_gain #(.DEFAULT_VOL(4'd12)) u_vol_gain`：输出 signed 24bit `vol_audio_l`、`vol_audio_r`；
- 唯一锚点 `u_hdmi_1_4b_transmitter_core_wrapper`：HDMI 发射核的 `I_audio_valid` 接 `audio_valid`，左右声道接 `vol_audio_l`、`vol_audio_r`。

因此 V2-01 必须旁路观察 `vol_audio_l`、`vol_audio_r` 和 `audio_valid`。不能改用 `wav_pcm_wire`，否则测试音不可见且无法反映最终音量；不能改用原始 `audio_left_data/right_data`，否则 WAV 与音量结果不完整。

### 2.2 时钟域

`audio_valid` 是 `video_clk` 域产生的 48kHz 单周期节拍。现有 WAV 播放器读口也已使用 `video_clk` 消费该节拍，这是 E9 后修复强沙沙声的稳定事实。

新数据通路必须使用：

- `clk = video_clk`；
- `rst = rst_all`；
- `sample_valid = audio_valid`。

不得把 `audio_valid` 直接送入 `audio_mclk` 域，避免重新引入窄脉冲 CDC 漏采。

### 2.3 现有电平条不可作为新波形数据源

`top_tf_hdmi_audio.v` 中现有 `audio_left_abs`、`audio_right_abs`、`audio_level_bar` 从原始 `audio_left_data/right_data` 计算，仅输出 4bit 电平，并不代表音量增益后的最终 PCM。本任务不修改该旧路径，也不复用其 4bit 结果。

### 2.4 可复用的 RAM 模式

`Project/src/user_source/hdl_source/SD/wav_stream_player.v` 在唯一锚点“标准 SDPRAM 推断模板”处使用独立写、读时钟过程实现双口 BRAM，已经过 TD 资源问题修复验证。`waveform_ram.v` 应复用这一存储结构，而不是使用大规模寄存器数组组合读。

波形缓存容量为：

- 逻辑深度 640；
- 每点 8bit；
- 总容量 5120bit，即 640byte；
- 物理数组使用 1024×8bit，共 8192bit，可落入 1 个 BRAM9K。

### 2.5 当前仿真与 TD 事实

- 当前仿真目录为 `Project/sim`，已有 SDRAM、FAT32、WAV、音量和真实时钟比等回归测试台；新测试资产继续放在该目录；
- 现有 `Project/sim/tb_wav_realclk.v` 使用 25MHz 读时钟和每 520 拍一次节拍，可参考其真实 48kHz 采样口径；
- 本机 ModelSim `vlog` 位于 `D:/Modelsim/Install/win64/vlog`；
- 厂商宏文件实际路径为 `D:/TD5.6.2/arch/eagle_macro.v`；
- 新增 RTL 尚未登记到 `Project/src/td_project/HDMI1.4b_Transmitter_v1.0.al`，应由用户在 TD GUI 中 Add Source，不手改可能被 TD 覆盖的 `.al` 文件；
- E10 已有约 −6.699ns setup 负裕量，hold 已通过。本任务只记录新增路径影响，不顺带修复既有时序。

## 3. 改动步骤

### 步骤 1：新增 `waveform_data.v` 的冻结接口

在 `Project/src/user_source/hdl_source/waveform_data.v` 新增纯数据处理模块：

输入：

- `clk`；
- `rst`；
- `sample_valid`；
- signed 24bit `sample_left`；
- signed 24bit `sample_right`。

输出：

- `wave_wr_en`；
- 10bit `wave_wr_addr`；
- 8bit `wave_wr_data`；
- `block_done`。

参数：

- `POINT_COUNT = 640`；
- `SAMPLES_PER_POINT = 1`。

`SAMPLES_PER_POINT` 只定义每点峰值窗口，不承担 60fps 帧同步。

### 步骤 2：实现左右声道饱和包络

1. 将左右输入分别按 signed 24bit 解释；
2. 正数保持，普通负数取二补码绝对值；
3. 特殊负满幅 `24'h800000` 饱和为 `24'h7fffff`，禁止回绕为负数或零；
4. 两路绝对值取最大值作为当前包络；
5. 不进行左右求和、平均或先求和再取绝对值，避免反相信号抵消与额外位宽。

### 步骤 3：实现窗口峰值、压缩和地址推进

1. 仅在 `sample_valid=1` 时更新窗口计数和峰值；无效时钟周期不推进任何采样状态；
2. 每 `SAMPLES_PER_POINT` 个有效样本形成一个点，取窗口最大包络；
3. 窗口最后一个样本到来时，写入值取“已有峰值”和“当前样本”的最大值，避免非阻塞赋值漏掉最后一个样本；
4. 当前默认 `SAMPLES_PER_POINT=1`，48kHz 下 640 点约覆盖 13.33ms，即约 75 块/秒；
5. 近似对数压缩使用最高有效位 `e` 与紧邻的 3bit 尾数 `m`：零输入输出 0；非零输入形成 `q = 1 + 8×e + m`，再用固定移位加法扩展到 8bit；
6. 压缩实现不得使用乘法、除法、取模或 DSP；必须保证静音为 0、最小非零输入非零、正负满幅为 255、全范围单调；
7. 写地址仅在实际写点时按 0→639→0 推进；
8. 地址 639 的实际写入同拍产生单周期 `block_done`；
9. 复位丢弃残缺块，地址、窗口计数与峰值回到初始状态。

### 步骤 4：新增 `waveform_ram.v`

在 `Project/src/user_source/hdl_source/waveform_ram.v` 新增物理 1024×8bit、逻辑使用 0~639 的简单双口 RAM：

写口：

- `wr_clk`、`wr_en`、10bit `wr_addr`、8bit `wr_data`。

读口：

- `rd_clk`、`rd_rst`、`rd_en`、10bit `rd_addr`、8bit `rd_data`、`rd_valid`。

时序约定：

- 同步读一拍延迟；第 N 拍提交 `rd_en` 与地址，第 N+1 拍 `rd_valid=1` 且 `rd_data` 对应该地址；
- 存储体不做整块复位清零，以免破坏 BRAM 推断；
- 消费者只在 `rd_valid=1` 时使用数据；
- 不依赖同地址同时读写时的 read-first/write-first 行为；
- 地址 640~1023 不得由正常数据通路写入。

### 步骤 5：顶层旁路集成

修改 `Project/src/user_source/hdl_source/top_tf_hdmi_audio.v`：

1. 在音量增益输出附近新增内部写口、读口与完成脉冲线网；
2. 例化 `waveform_data`，连接 `video_clk`、`rst_all`、`audio_valid`、`vol_audio_l`、`vol_audio_r`；
3. 例化 `waveform_ram`，写口接数据模块；当前读写时钟均接 `video_clk`；
4. V2-01 阶段读口禁用、地址置 0，读数据与 `rd_valid` 只接内部未消费线网；
5. HDMI 发射核的 `audio_valid`、`vol_audio_l`、`vol_audio_r` 保持原样；
6. 不修改现有 `audio_level_bar`、视频和 OSD 路径；
7. 不增加 `keep`、调试引脚或数码管显示来强制保留无消费者的 RAM。综合器若裁剪该旁路，按预期记录，V2-02 接入读口后再确认资源。

### 步骤 6：建立当前工程仿真资产

在 `Project/sim` 新增：

- `tb_waveform_data.v`；
- `tb_waveform_ram.v`；
- `tb_waveform_path.v`。

测试台使用 Verilog-2001 自检方式，不使用 SystemVerilog SVA，不新增代码注释。

## 4. 验收方式

### 4.1 `tb_waveform_data.v`

必须覆盖：

1. 复位期间无写入、无完成脉冲，复位后首个地址为 0；
2. 640 个静音有效样本产生地址 0~639、数据全 0、一次单拍完成；
3. 第 641 点回到地址 0；
4. `sample_valid` 插空时不写、不推进窗口和地址；
5. `+1` 与 `-1` 映射一致且非零；
6. `+0x7fffff` 与 `-0x800000` 均精确映射为 255；
7. 左小右大、左大右小均取较大幅值；交换声道结果不变；
8. 左右等幅反相不抵消；
9. 低幅连续值、所有二次幂边界及尾数分段边界满足非递减；
10. `SAMPLES_PER_POINT=4` 时，峰值位于窗口首、中、末均得到相同结果，夹杂无效周期时仍只统计 4 个有效样本；
11. 块中途复位后丢弃残块并从地址 0 重启；
12. 连续两块各自地址完整、完成脉冲各一拍。

测试黄金值应由独立参考计算或常量表产生，不读取 DUT 内部中间信号自证。

### 4.2 `tb_waveform_ram.v`

必须覆盖：

1. 地址 0、1、639 写入不同数据并正确读回；
2. `rd_data` 与请求地址严格相差一拍，`rd_valid` 同步；
3. `rd_en=0` 后下一拍 `rd_valid=0`；
4. 地址 639 后读取 0 不交换、不重复；
5. 第二轮覆盖地址 0 不误伤其他地址；
6. 独立写读时钟基本工作，避免对同地址并发返回值作假设。

### 4.3 `tb_waveform_path.v`

串接数据模块和 RAM，写满 640 点后逐地址读取，与独立压缩黄金向量逐项比较，验证写地址、写数据、同步读和边界的一致性。

### 4.4 本地 ModelSim

1. 使用 `D:/Modelsim/Install/win64/vlog` 编译新增模块和三个测试台；
2. 每个测试台必须明确输出 PASS 后结束；
3. 执行当前工程完整 HDL 编译与顶层 elaboration；
4. 需要解析 Anlogic 原语时加入 `D:/TD5.6.2/arch/eagle_macro.v`；
5. 允许既有加密 HDMI/SDRAM IP warning，但新增模块和顶层新增连接不得出现未知模块、隐式线网、位宽/符号错误、多驱动、锁存或地址越界；
6. 本轮不执行 TD 综合、布局布线或 bitstream。

### 4.5 用户 TD 检查

用户需要：

1. 在 TD GUI 中 Add Source：`waveform_data.v`、`waveform_ram.v`，不加入 `Project/sim` 下的测试台；
2. 确认两个文件参与综合与布局布线，顶层仍为 `top`；
3. 执行综合检查，无新增 black box、错误、多驱动或锁存；
4. 确认压缩逻辑不新增 DSP；
5. 若 RAM 层级保留，确认推断为 BRAM而非大量 LUT/REG；若因读口无消费者被裁剪，记录为预期，不强行保留，也不以 BRAM 数量未增长判失败；
6. 如查看时序，区分 E10 既有约 −6.699ns setup 遗留与本任务新增 `waveform_*` 路径。

### 4.6 完成判据

以下全部满足后，V2-01 可标记为“通过（模块级；可视集成验收归 V2-02）”并归档：

- 三个自检测试台全部通过；
- 完整顶层编译与 elaboration 通过；
- 用户已在 TD GUI 登记两个新 RTL；
- 用户 TD 综合检查无新增错误；
- 音频与视频原连接未改变；
- 未新增代码注释。

V2-01 不要求 `phy_1`、bitstream 或单独上板，不建立 E11；E10 保持为当前上板稳定点。

## 5. 回退点与风险

### 5.1 回退点

代码和硬件回退基线均为 E10。由于当前工作区存在既有未跟踪迁移内容和其他改动，回退时不得使用会覆盖整个工作区的操作。

若 V2-01 出现问题：

1. 从顶层移除两个新增实例与对应内部线网；
2. 从 TD 工程 source list 移除两个新增 RTL；
3. 不触碰 WAV、音量、HDMI、OSD、SDRAM 和用户其他既有改动；
4. 复核 E10 的 WAV/测试音、16 档音量、图片、切图、转场和 OSD 行为。

### 5.2 风险

- 数据源选错：只能采最终 `vol_audio_l/r`，不能采旧电平条或 WAV 单一路径；
- 时钟域选错：采集必须使用 `video_clk`，否则可能重现 `audio_valid` 窄脉冲漏采；
- 负满幅绝对值溢出：`24'h800000` 必须单独饱和；
- 左右声道抵消：必须分别取绝对值后取最大值；
- 窗口最后一个样本遗漏：提交点必须显式比较当前包络与已存峰值；
- 地址边界错位：完成脉冲必须与地址 639 实际写入对齐；
- RAM 推断异常：存储模板需保持简单双口形式，不整块复位；
- RAM 被裁剪：V2-01 没有读消费者，允许综合优化，不得为强行保留增加副作用；
- 更新率误述：默认约 75 块/秒，不宣称已经实现 60fps；
- 单 RAM 滚动写读撕裂：V2-01 不读，后续提交与平滑由 V2-03处理；
- 时序归因错误：E10 已有 setup 负裕量，本任务不混做既有时序修复；
- TD 工程登记丢失：必须由用户 GUI Add Source，不依赖手改 `.al`。

## 6. 任务过程记录

- 2026/10/11：按新版 V2 方案完成接手。确认 V2 正文实际有 25 项，用户决定采用 `V1-NN`/`V2-NN` 阶段化稳定键；已将首任务确定为 V2-01。
- 2026/10/11：读取当前顶层、音量增益、WAV 缓冲及旧真实时钟比测试台，确认数据源为 `vol_audio_l/r + audio_valid`，采集域为 `video_clk`，缓存容量为 5120bit/640byte。
- 2026/10/11：建立本推进方案。当前仅完成方案和文档治理，尚未修改 RTL、尚未运行仿真或 TD。下一步必须在用户明确要求开始实现后，严格按第 3 节逐步执行。
- 2026/10/11：用户已将历史仿真资产补到 `Project/sim`。核对确认该目录包含 WAV、音量、FAT32、SDRAM 等既有测试台；本任务后续新增的三个波形测试台统一放在 `Project/sim`，不再使用 `Project/src/sim` 或历史副本路径。
- 2026/10/11：新增 `waveform_data.v` 与 `waveform_ram.v`，未撰写代码注释。数据模块使用 `video_clk` 域的 `audio_valid`，采集最终 signed 24bit `vol_audio_l/r`；实现负满幅饱和绝对值、左右包络取最大值、可参数化窗口峰值、近似对数压缩、0~639 写地址与块完成脉冲。RAM 为 1024×8bit 标准简单双口结构，逻辑使用 0~639，同步读一拍并输出 `rd_valid`。
- 2026/10/11：修改 `top_tf_hdmi_audio.v`，在 `u_vol_gain` 后旁路例化波形数据与 RAM；HDMI 发射核仍直接使用原 `audio_valid`、`vol_audio_l/r`，旧电平条、视频、OSD、SDRAM、WAV 链路均未改。V2-01 读口按方案禁用，允许综合裁剪。
- 2026/10/11：新增 `Project/sim/tb_waveform_data.v`、`tb_waveform_ram.v`、`tb_waveform_path.v`。ModelSim 10.1c 自检结果为 `WAVEFORM_DATA PASS`、`WAVEFORM_RAM PASS`、`WAVEFORM_PATH PASS`；覆盖静音、正负满幅、声道交换/反相、单调边界、窗口峰值、复位、两块回绕、同步读和端到端 640 点写读。
- 2026/10/11：音频回归结果为 `tb_wav_player` 两场景 PASS、`tb_wav_realclk` REALCLK PASS、`tb_audio_volume` PASS，未发现 WAV 样本顺序、真实时钟比或数字音量回归。
- 2026/10/11：按 TD source 清单进行完整编译。直接 elaboration 被既有加密 SDRAM 核在 ModelSim 10.1c 下的 protected-region/无尺寸常量兼容问题阻塞；按项目 E4-1 既有口径，仅用临时 SDRAM 接口 stub 排除该厂商核后，顶层 `vopt` 完整展开成功，`waveform_data`、`waveform_ram` 均成功装载。输出仅有既有 FIFO 端口与地址位宽、加密 HDMI warning，无新增波形模块 warning。临时 stub 与本轮 ModelSim 工作库已删除。
- 2026/10/11：`git diff --check` 通过；确认两个新增 RTL 和三个新增测试台均无注释。只读复核提出 `vol_audio_l/r` 由 audio_mclk 域音量寄存器组合影响、被 video_clk 域采样的既有 CDC 边界；核对确认 HDMI 核与 V2-01 都以同一 `audio_valid`、同一 `video_clk` 采样同一最终 PCM，因此本任务不另加会造成波形/声音错位的多位同步快照，该风险继续归入 E10 既有音频时序遗留。
- 2026/10/11：用户已在 TD GUI 中加入 `waveform_data.v`、`waveform_ram.v` 并完成 `syn_1`。工程清单登记两文件的 CompileOrder 为 52/53；综合日志显示成功分析 44 个源文件，两个模块均成功 elaboration，`memory` 被识别为 RAM；全工程无综合错误，LATCH=0，DSP 仍为 13。由于 V2-01 读口固定关闭且无消费者，后续优化未把波形缓存保留为 BRAM，BRAM9K 仍为 31，层级报告中 `u_waveform_ram` 仅保留优化后的 152 LUT/72 REG；这符合本方案允许的无消费者优化口径，真正 BRAM 保留与资源增长留 V2-02 接入读口后确认。
- 2026/10/11：本次综合资源为 LUT 13241/19600、REG 7478/19600、BRAM9K 31/64、DSP 13/29；综合时序 setup WNS −6.302ns、TNS −1,145,885ps、违例端点 931，hold WNS +0.471ns、无 hold 违例。最差路径仍在 `ext_mem_clk` 与 `sd_card_clk`，报告未显示 `waveform_*` 成为最差路径。V2-01 冻结判据全部满足，任务按模块级通过完成；可视上板与 BRAM 最终保留归 V2-02，E10 继续作为当前上板稳定点。
