# Anlu 小步推进方案 V2-02：波形渲染

## 1. 背景与目标

本任务对应 `Project/doc/项目方案.md` 的 V2-02，前置 V2-01 已按模块级判据完成并归档。当前硬件稳定点仍为 E10。

本次单一目标是把 V2-01 生成的单路左右最大包络显示成全宽 640px、高 24px 的填充式波形，并实现四级青绿色渐变、约 80% alpha 和白色峰值保持线。

根据当前界面真实布局，本次冻结显示区域为：

- 水平：`x=0~639`；
- 垂直：`y=408~431`；
- 右侧电平面板截止于 `y=403`，中间保留 4px；
- 滚动字幕从 `y=432` 开始，波形不与字幕重叠。

本次必须让 V2-01 waveform RAM 和新增 peak RAM 各落入一个 BRAM9K，不允许以 640 项寄存器或 LUT 数组替代。

本次不做：

- 不修改 V2-01 的 PCM 采集、压缩与 640 点循环逻辑；
- 不做双缓冲、60fps 稳定提交、帧间平滑或冻结快照，这些属于 V2-03；
- 不消除单份 waveform RAM 边写边读可能产生的轻微局部跳变；
- 不移动、删除或重构现有滚动字幕、右侧电平条及左上 OSD；
- 不推进 OSD Buffer、新状态栏、多曲目、设置界面或其他 V2 任务；
- 不修改 WAV、音量、HDMI 音频、SD/FAT32、SDRAM 和转场状态机；
- 不处理 E10 既有 setup 负裕量与残留轻微沙声；
- 不新增代码注释；
- 本地不运行 TD `syn_1`、`phy_1` 或 bitstream，这些由用户执行。

V2-02 只有在 ModelSim、自检回归、两块 BRAM 综合确认、用户布局布线/bitstream、上板显示和使用说明同步全部通过后才能完成归档。通过后可登记 E11；在此之前 E10 是唯一硬件回退点。

## 2. 当前代码事实

### 2.1 V2-01 数据通路

`Project/src/user_source/hdl_source/waveform_data.v` 已实现：

- 在 `video_clk` 域按 `audio_valid` 采集最终音量增益后的 signed 24bit `vol_audio_l/r`；
- 左右声道分别求饱和绝对值后取最大值；
- 输出 `wave_wr_en`、`wave_wr_addr[9:0]`、`wave_wr_data[7:0]`；
- 地址严格循环 `0~639`；
- `wave_block_done` 与地址 639 的实际写入对齐；
- 默认约 75 个数据块/秒，尚未与 60fps 视频帧锁定。

`Project/src/user_source/hdl_source/waveform_ram.v` 当前为：

- 物理 1024×8bit，逻辑使用 0~639；
- 写口由 `waveform_data` 持续写入；
- 读口为同步一拍，第 N 拍输入 `rd_en/rd_addr`，第 N+1 拍输出 `rd_valid/rd_data`；
- 存储体不做整块复位。

顶层 `u_waveform_ram` 当前读口固定关闭。V2-01 的 TD 综合曾识别 `memory` 为 RAM，但因没有读消费者而将其优化，BRAM9K 保持 31，层级中只留下优化后的 152 LUT/72 REG。V2-02 接入真实读消费者后必须确认其最终落入一个 BRAM9K。

### 2.2 当前视频链路与插入点

`Project/src/user_source/hdl_source/top_tf_hdmi_audio.v` 当前链路为：

`video_delay → vout_data_raw → display_image_area 门控 → vout_data_base → video_osd_overlay → vout_data → video_rgb_to_axis_640x480 → HDMI`

V2-02 的唯一插入点为：

`vout_data_base → waveform_render → video_osd_overlay → video_rgb_to_axis_640x480`

这样波形会经过 `video_osd_overlay` 内现有亮度、对比度、reveal 和全画面 fade，字幕、面板和右侧电平条仍绘制在波形上层。若把波形放在 OSD 后面，转场黑场时可能出现波形悬浮，因此不采用。

### 2.3 坐标与布局

顶层已有：

- `video_x_cnt`、`video_y_cnt`；
- `video_x_pos`、`video_y_pos`；
- 原始 `vs/de`；
- `e2_frame_pulse = e2_vs_d && !vs`。

`Project/src/user_source/hdl_source/video_osd_overlay.v` 的实际布局为：

- 滚动字幕背景 `y=432~471`；
- 字幕文字 `y=444~459`；
- 右侧音频面板 `y=184~403`。

因此方案示例 `y=456~479` 会覆盖滚动字幕。`y=408~431` 是当前界面中唯一无需移动既有元素、又可容纳完整 24px 的全宽区域，已在 `项目方案.md` 受控修订。

### 2.4 视频同步读对齐要求

waveform RAM 为同步读。第 N 拍请求地址 x 后，第 N+1 拍数据才有效。V2-02 必须在第 N 拍同步寄存输入 RGB、x、y、vs、de，并在第 N+1 拍用返回数据合成。

`video_osd_overlay` 与 `video_rgb_to_axis_640x480` 都必须改接同一组延迟后的 vs/de。若只延迟 RGB，会导致波形水平错一列、行首继承上一行 x=639 数据，且 AXIS 的 user/last/valid 与 RGB 错位。

### 2.5 综合资源基线

V2-01 最新 `syn_1`：

- LUT 13241/19600；
- REG 7478/19600；
- BRAM9K 31/64；
- DSP 13/29；
- setup WNS −6.302ns；
- hold WNS +0.471ns。

V2-02 预期新增两个 BRAM9K：waveform RAM 一个、peak RAM 一个；DSP 必须保持 13。已有 setup 不干净，因此高度映射、颜色、alpha 和峰值控制不得形成一条过长组合路径。

## 3. 改动步骤

### 步骤 1：新增 `waveform_peak_ram.v`

在 `Project/src/user_source/hdl_source/waveform_peak_ram.v` 新增单时钟简单双口 RAM：

输入/输出：

- `clk`、`rst`；
- A 读口：`rd_en`、`rd_addr[9:0]`、`rd_data[5:0]`、`rd_valid`；
- B 写口：`wr_en`、`wr_addr[9:0]`、`wr_data[5:0]`。

约束：

- 物理 1024×6bit，逻辑只使用 0~639；
- 同步读一拍；
- `rst` 只清 `rd_data/rd_valid`，不循环清整个数组；
- 不依赖同地址同拍读写返回旧值或新值；
- 目标为独立占用一个 BRAM9K；
- 禁止回退成 `reg peak_val[0:639]` 的并行寄存器/LUT实现。

### 步骤 2：新增 `waveform_render.v` 冻结接口

输入：

- `I_clk`、`I_rst`；
- `I_frame_pulse`、`I_wave_block_done`；
- `I_vs`、`I_de`、`I_x[9:0]`、`I_y[9:0]`、`I_rgb[23:0]`；
- waveform RAM 返回：`I_wave_rd_data[7:0]`、`I_wave_rd_valid`；
- peak RAM 返回：`I_peak_rd_data[5:0]`、`I_peak_rd_valid`。

输出：

- `O_vs`、`O_de`、`O_rgb[23:0]`；
- waveform RAM：`O_wave_rd_en`、`O_wave_rd_addr[9:0]`；
- peak RAM A 口：`O_peak_rd_en`、`O_peak_rd_addr[9:0]`；
- peak RAM B 口：`O_peak_wr_en`、`O_peak_wr_addr[9:0]`、`O_peak_wr_data[5:0]`。

模块内部统一承担：

- waveform RAM 读口分时仲裁；
- peak RAM 串行初始化；
- 每帧消隐期峰值扫描与写回；
- 视频元数据一拍对齐；
- 高度、渐变、alpha 和峰值白线合成。

### 步骤 3：有效性门控与峰值清零

1. `wave_ready` 复位后为 0，收到首个 `I_wave_block_done` 后置 1；
2. `wave_ready=0` 时不显示波形、不启动峰值扫描，只输出延迟后的原视频；
3. peak RAM 复位后进入 `P_CLEAR`，地址 0→639 每拍写零；
4. 地址 639 写入后置 `peak_init_done`，进入 `P_IDLE`；
5. 清零共 640 拍，25MHz 下约 25.6µs；清零期间忽略帧脉冲；
6. 不访问或清除地址 640~1023。

### 步骤 4：峰值后台状态机

固定状态：`P_CLEAR → P_IDLE → P_SCAN → P_DRAIN → P_IDLE`。

`P_IDLE`：

- 仅在 `peak_init_done && wave_ready` 时响应一次 `I_frame_pulse`；
- 每次扫描地址强制从 0 开始。

`P_SCAN`：

- 只在 `I_de=0` 时同时请求 waveform RAM 与 peak RAM 相同地址；
- 地址 0→639 连续发出；
- 同步保存地址标签；
- 每列返回后计算并写回：
  - `height=floor(amplitude×24/255)`；
  - `current_q=height<<1`；
  - `decayed_q=(old_peak_q==0)?0:old_peak_q-1`；
  - `new_peak_q=max(current_q,decayed_q)`。

`P_DRAIN`：

- 停止新请求；
- 直到地址 639 的最后一次写回真实发生，才返回 `P_IDLE`；
- 若有效区意外提前到来，停止发新请求、排空已发管线，下一帧重新从地址 0 开始。

正常扫描约 640 拍加少量排空拍，远小于 480p 垂直消隐预算。

### 步骤 5：RAM端口分工

waveform RAM：

- 写口始终归 `waveform_data`；
- 读口在消隐扫描和活动波形区渲染之间分时；
- 扫描状态优先只在消隐期使用；
- 活动区仅在 `x=0~639、y=408~431` 请求当前列；
- 其余时间 `rd_en=0`。

peak RAM：

- A口在消隐期读旧峰值，在活动波形区读当前列峰值；
- B口在 `P_CLEAR` 写零、在扫描返回阶段写更新值；
- 活动区不写 peak RAM；
- 清零优先于扫描写回。

扫描和活动渲染不得同拍争用读口。waveform RAM写读同址时不依赖器件返回模式；轻微实时跳变留给V2-03。

### 步骤 6：一拍视频管线

第 N 拍：

- 为当前 x 发出 waveform/peak 读请求；
- 同步寄存 `I_rgb`、`I_x`、`I_y`、`I_vs`、`I_de` 和波形区域标志。

第 N+1 拍：

- 使用 RAM 返回数据与延迟元数据合成；
- 输出 `O_rgb/O_vs/O_de`。

不得再多打一拍 RAM 数据。OSD 和 AXIS 必须同时改接 `O_vs/O_de`，确保行首、行尾、帧首与 RGB 一致。

### 步骤 7：高度、渐变、alpha与峰值线

高度映射：

- `n=(A<<4)+(A<<3)`；
- `height=(n+1+(n>>8))>>8`；
- 0→0，255→24，全范围单调；
- 不使用乘除或DSP。

填充判断：

- 底边为 432；
- 仅当 `height!=0 && y>=432-height && y<432` 时绘制；
- 静音不显示底部假线。

四级渐变：

- `y=408~413`：`#5BC0BE`；
- `y=414~419`：`#50AEAC`；
- `y=420~425`：`#459C9A`；
- `y=426~431`：`#3A8A88`。

使用范围比较选择常量色，不综合除6。

alpha：

- `out=(13×wave+3×video+8)>>4`；
- `13×wave_color` 预计算为常量；
- `3×video` 使用移位加法；
- 每通道使用足够中间位宽，禁止溢出回绕；
- 不新增DSP。

峰值线：

- `peak_q` 为 Q5.1，范围0~48；
- `peak_px=(peak_q+1)>>1`；
- `peak_q=0` 时不画；否则 `peak_y=432-peak_px`；
- 白线优先于填充，直接输出 `24'hFFFFFF`；
- 每帧减1个Q单位，对应0.5px/帧，静音后最多约48帧衰减至零。

### 步骤 8：顶层集成

修改 `Project/src/user_source/hdl_source/top_tf_hdmi_audio.v`：

1. 新增 `vout_data_wave`、`wave_vs`、`wave_de` 及两块RAM端口线网；
2. `u_waveform_ram` 读口改接 `waveform_render`；
3. 例化 `waveform_peak_ram`；
4. 例化 `waveform_render`，输入原始 `vs/de`、`video_x_cnt[9:0]`、`video_y_cnt`、`vout_data_base`、`e2_frame_pulse`、`wave_block_done`；
5. `video_osd_overlay` 改接 `vout_data_wave/wave_vs/wave_de`；
6. `video_rgb_to_axis_640x480` 同样改接 `wave_vs/wave_de`，RGB仍接 `vout_data`；
7. 原始坐标、`e2_frame_pulse`、SDRAM `frame_tick` 和转场FSM保持原始时序；
8. 不修改HDMI音频连接和`waveform_ram.v`接口。

## 4. 验收方式

### 4.1 新增测试台

新增：

- `Project/sim/tb_waveform_peak_ram.v`；
- `Project/sim/tb_waveform_render.v`。

`tb_waveform_peak_ram` 覆盖：

- 地址0、1、639写读；
- 一拍同步读与`rd_valid`；
- 独立读写不同地址；
- `rd_en=0`时下一拍`rd_valid=0`；
- 不对同址并发返回值作假设。

`tb_waveform_render` 连接真实 waveform RAM、peak RAM 与渲染器，覆盖：

1. 复位后 peak 地址0~639逐一清零，清零前帧脉冲不启动扫描；
2. 首个`wave_block_done`前只旁路，不显示随机内容；
3. 每帧扫描从0开始，0~639不重不漏，地址639实际写回后才结束；
4. 高度输入0/255和0~255全遍历，范围0~24且单调；
5. 当前峰高于旧峰、低于旧峰、旧峰0不下溢；连续静音每帧准确减1个Q单位；
6. x=0/639、y=407/408/431/432边界；
7. 四级颜色与多组背景RGB的alpha黄金值；
8. `peak_q=0`无白线，奇偶Q值位置正确，白线不透明；
9. 相邻列不同幅值时不交换、不固定偏移；新行x=0不继承上一行x=639；
10. RGB、VS、DE同步延迟一拍；扫描与渲染请求不冲突；扫描在消隐预算内完成。

### 4.2 本地ModelSim与回归

- 新模块和两个新测试台必须明确PASS；
- 回归V2-01三个测试台；
- 回归`tb_wav_player`、`tb_wav_realclk`、`tb_audio_volume`；
- 完整HDL编译与顶层elaboration；加密SDRAM若仍不兼容ModelSim 10.1c，沿用V2-01临时接口stub口径，完成后删除；
- 新模块不得出现隐式线网、位宽/符号错误、多驱动、latch、地址越界、非预期乘法器或代码注释。

### 4.3 用户TD `syn_1`

用户在TD GUI中Add Source：

- `waveform_render.v`；
- `waveform_peak_ram.v`。

测试台不加入TD。综合硬门槛：

- 无新增错误、black box、多驱动、latch；
- `u_waveform_ram`与peak RAM各占1个BRAM9K，BRAM总量预期31→33；
- DSP保持13；
- 不出现峰值数组展开为大量LUT/REG；
- waveform渲染不成为新的异常长路径。

如果任一RAM未落BRAM、BRAM不是预期+2或峰值展开为逻辑资源，立即暂停，不运行`phy_1`、不生成bitstream、不接受寄存器数组绕过，只单因素修正RAM映射。

### 4.4 用户`phy_1`与bitstream

仅在综合存储门槛通过后由用户执行：

- 记录资源、setup/hold与新增waveform路径；
- 确认hold无新增违例；
- 确认仍为两个新增BRAM、DSP增量0；
- 生成bitstream。

### 4.5 上板最终验收

布局：

- 波形完整覆盖x=0~639、仅位于y=408~431；
- 与右侧电平条相隔4px；
- 不覆盖y=432~471滚动字幕。

幅值：

- MUSIC.WAV和测试音均能驱动波形；
- 音量档变化时高度同步；
- 音量0时填充消失，旧峰值最多约48帧衰减完；
- 大音量接近24px。

视觉：

- 四段青绿色由上到下正确；
- 背景图可透过填充；
- 峰值线白色不透明并以约0.5px/帧下降。

管线与转场：

- 无固定一列偏移、行首毛刺、断行或HDMI失锁；
- reveal/fade连同波形一起作用；
- 字幕与面板保持在波形上层；
- AXIS帧首、行末稳定。

回归：

- 图片装载1→3→7→F；
- 手动切图、自动轮播、方向、reveal/fade；
- WAV、测试音、16档音量；
- 亮度/对比度、现有OSD；
- 拔卡保持与重插恢复均正常。

允许把单份waveform RAM边写边读造成的轻微局部跳变记录并留给V2-03；固定错位、明显闪烁或峰值异常不能通过。

## 5. 回退点与风险

### 5.1 回退点

代码与硬件回退基线均为E10，V2-01保留。V2-02通过前不建立新稳定点。

失败时只回退本任务范围：

1. 从顶层移除`waveform_render`与`waveform_peak_ram`；
2. 恢复waveform RAM读口固定关闭；
3. 恢复OSD和AXIS使用原始vs/de；
4. 从TD source list移除两个V2-02新文件；
5. 恢复本任务关联的进度、方案与使用说明增量；
6. 不触碰V2-01、WAV、音量、SDRAM、OSD其他逻辑及用户已有改动。

当前工作区已有大量迁移与未跟踪内容，禁止使用会覆盖整个工作区的回退操作。

### 5.2 主要风险

- waveform未写满导致随机内容：首个`wave_block_done`前禁止显示和峰值扫描；
- peak上电随机值：串行清零0~639，完成前不显示；
- 同步读错一列：RGB、坐标、vs/de统一延迟并使用地址标签；
- 扫描起点或尾部丢失：每帧强制从0开始，地址639真实写回后才结束；
- 活动显示与扫描争用：扫描只在de=0发请求，活动区不写peak；
- 同址waveform写读：不依赖返回模式，轻微跳变留V2-03；
- Q5.1峰值下溢或底边白线：0饱和并对`peak_q=0`禁画；
- alpha引入DSP或长路径：颜色乘积常量化，视频只做移位加法；
- RAM未落BRAM：综合硬停止，不用LUT/REG绕过；
- OSD/AXIS控制只改一处：两者必须同时接同一组延迟vs/de；
- 既有setup未收敛：若waveform成为新增异常路径，暂停并单独规划流水化，不与本任务临时混改；
- 单RAM动态撕裂：仅轻微局部跳变可留V2-03，明显闪烁不可通过。

## 6. 任务过程记录

- 2026/10/11：V2-01 已模块级通过并归档。读取当前顶层、OSD、AXIS、waveform RAM、最新综合报告和 V2-02 冻结定义，确认原示例区域 `y=456~479` 与现有滚动字幕 `y=432~471` 冲突。
- 2026/10/11：确定 V2-02 波形区域为 `x=0~639、y=408~431`，位于右侧电平条下方4px、滚动字幕正上方；受控修订 `项目方案.md` 并记录方案变更。
- 2026/10/11：确定波形插在 `vout_data_base` 与 `video_osd_overlay` 之间；峰值采用独立1024×6bit Q5.1 BRAM，消隐期串行更新。两块RAM未各自落入BRAM9K时，综合阶段硬停止。
- 2026/10/11：建立本推进方案并在进度表登记为“进行中（仅建立方案，RTL未改）”。
- 2026/10/11：用户要求开始执行。新增 `waveform_peak_ram.v`，实现 1024×6bit 单时钟简单双口 RAM；新增 `waveform_render.v`，实现 peak 串行清零、wave有效门控、消隐期 0~639 扫描、Q5.1峰值更新、一拍视频元数据对齐、四级渐变、13/16 alpha 与白色峰值线。两个新增RTL未撰写代码注释。
- 2026/10/11：新增 `Project/sim/tb_waveform_peak_ram.v` 与 `tb_waveform_render.v`。模块测试结果为 `WAVEFORM_PEAK_RAM PASS`、`WAVEFORM_RENDER PASS`，覆盖清零、扫描、末列写回、0.5px衰减、0~255高度映射、区域边界、四级渐变、alpha和一拍视频对齐。
- 2026/10/11：修改 `top_tf_hdmi_audio.v`，将wave RAM读口接入渲染器，例化peak RAM与渲染器；视频链改为 `vout_data_base → waveform_render → video_osd_overlay → AXIS`，OSD与AXIS均使用同一组延迟后的vs/de，原坐标、帧脉冲、SDRAM刷新与音频连接保持不变。
- 2026/10/11：完整回归通过：V2-01三个测试、V2-02两个测试、`tb_wav_player`两场景、`tb_wav_realclk`、`tb_audio_volume`全部PASS。首次顶层编译发现波形线网在使用后才声明而形成Verilog隐式网冲突，已仅将声明前移到统一声明区；修正后使用临时SDRAM接口stub的完整顶层`vopt`成功，新增两个模块均装载，只有工程既有warning。stub及全部临时ModelSim工作库已删除。
- 2026/10/11：`git diff --check`通过；确认两个新增RTL和两个新增测试台均无注释。快速只读复核限定检查 `waveform_render.v`、`waveform_peak_ram.v` 与顶层接线，未发现能明确导致功能或综合错误的高置信问题。
- 2026/10/11：用户完成 TD 综合、布局布线、bitstream 和上板。原有图片、切图、音频、音量等功能未见异常，波形能够随音频变化；但视觉验收未通过：24px 单边波形紧贴滚动字幕、幅度变化偏小、持续实时改写使整体显得杂乱，用户决定下一版改为字幕上方 48px 居中对称波形并移除旧右侧电平条。
- 2026/10/11：TD 报告确认冻结资源判据未满足：`u_waveform_ram` 被推断为 Logic DRAM，占 1347 LUT/80 REG；`u_waveform_peak_ram` 被推断为 Logic DRAM，占 1030 LUT/7 REG；BRAM9K 仍为31。综合 LUT 16204/19600，布局后 LUT 16565/19600（84.52%），Slice 利用率超过90%，工具跳过 hold 修复；最终 setup WNS −6.699ns，hold WNS −0.012ns、4个违例端点。V2-02 因视觉路线和存储资源路线均未达到冻结判据，状态调整为暂停实验版本，不建立E11，E10继续作为硬件稳定点。后续由V2-03先以显式双BRAM和原子帧提交修复资源与稳定性，再实现平滑和48px对称视觉。
