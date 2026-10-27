# Anlu 小步推进方案 V2-03：双BRAM帧同步平滑与48px对称波形

## 1. 背景与目标

V2-02 已完成综合、布局布线、bitstream和上板，原功能正常且波形随音频变化，但视觉和资源冻结判据均未通过：24px单边波形紧贴字幕、幅度偏小、画面杂乱；waveform/peak两个数组均落入Logic DRAM/LUT，BRAM仍为31，布局后LUT 16565/19600，Slice利用超过90%，最终hold WNS −0.012ns并有4个违例端点。V2-02已作为暂停实验版本归档，不建立E11，E10继续作为硬件稳定点。

用户已选择下一版采用：

- 全宽48px居中上下对称波形；
- 放在滚动字幕上方；
- 移除右侧旧电平条；
- 继续优化稳定性和美观度。

V2-03的单一目标是用两个显式BRAM9K实现前后台波形帧缓存，按真实视频窗口稳定生成640列，在消隐期完成空间/时间滤波后原子提交，并最终渲染为`x=0~639、y=380~427`的居中对称波形。

本任务不做FFT、多声道独立波形、OSD Buffer、新状态栏、多曲目、菜单，也不重构WAV、音量、SD/FAT32、SDRAM或转场状态机；不进行全局setup专项整改；不新增代码注释；本地不运行TD综合、布局布线或bitstream。

任务严格分三阶段，每阶段独立硬停止：

1. R：显式双BRAM与原子提交；
2. S：动态采样、横向/时间平滑；
3. V：48px对称视觉与移除旧电平条。

阶段R资源门槛未通过时，不得进入阶段S；阶段S未通过时，不得进入阶段V。

## 2. 当前代码事实

### 2.1 V2-02资源与时序事实

最新TD报告：

- `u_waveform_ram`：1347 LUT、80 REG、0 BRAM；
- `u_waveform_peak_ram`：1030 LUT、7 REG、0 BRAM；
- 综合LUT 16204/19600（82.67%）；
- 布局后LUT 16565/19600（84.52%）；
- BRAM9K 31/64；DSP 13/29；
- Slice利用超过90%，工具跳过hold修复；
- 最终setup WNS −6.699ns；
- 最终hold WNS −0.012ns、4个违例端点。

综合日志明确把两个数组报告为`Infer Logic DRAM`。因此当前`reg memory[]`模板不能作为正式路线继续叠加。

### 2.2 可复用的显式BRAM模式

`Project/src/user_source/hdl_source/SD/bmp_read.v`中的`up_row_mem`显式例化`EG_LOGIC_BRAM`并已上板验证资源正确，关键参数包括：

- 10bit地址、1024深度；
- `MODE("PDPW")`；
- `REGMODE_A/B("NOREG")`；
- `RESETMODE("SYNC")`；
- `IMPLEMENT("9K")`。

V2-03应基于该已验证原语模式构建两个8bit waveform bank，不再依赖TD自动推断。

### 2.3 当前采样与显示问题

`waveform_data.v`当前每个`audio_valid`形成一个点，640点约13.33ms，即约75块/秒；视频帧率约`25MHz/(800×525)=59.52Hz`。`waveform_render`直接读取正在写入的单缓存，导致同一视频帧可能混合不同音频块，表现为局部乱跳和杂乱。

实际每视频帧约有806.4个48kHz样本，不能硬编码固定800后跨帧累积相位。V2-03需按上一窗口实际接受样本数自适应映射，并在每轮重置相位。

### 2.4 当前视觉与旧电平条

现有V2-02区域为`y=408~431`，只有24px单边填充。`video_osd_overlay.v`仍含右侧`x=598~631、y=184~403`的旧电平面板；扩大到48px后将在右下区域重叠，因此最终阶段必须删除该电平条及顶层旧4bit电平统计链路。

## 3. 改动步骤

### 阶段R：显式双BRAM与原子提交

#### R1：重构`waveform_ram.v`

用两个显式`EG_LOGIC_BRAM`组成bank0/bank1：

- 每块物理1024×8bit，逻辑地址0~639；
- 两块均使用`video_clk`；
- 每块Port A固定为写口，Port B固定为读口；
- 不整块复位，不访问640~1023；
- `front_sel`决定front，另一块为back；
- 活动区front Port B读显示，back Port A写采样；
- 不依赖同址读写语义。

提供明确的一拍读返回标签与`rd_valid`，测试台使用行为模型验证，TD生产实例使用显式原语。

#### R2：暂时保留V2-01块采集但改写back

阶段R只验证资源与原子性：

- `waveform_data`继续生成640点块；
- 所有写入定向到back bank；
- `wave_block_done`只置`back_pending`，不立即切换；
- 在`e2_frame_pulse`且处于消隐期时，若`back_pending`，原子翻转`front_sel`并清pending；
- 活动区内front_sel保持不变；
- 首个完整块前`front_valid=0`，只旁路原视频；
- 删除顶层`waveform_peak_ram`实例和peak读写端口；
- `waveform_render`阶段R临时移除峰值通路，保留简单读取front的渲染，以验证无半帧改写。

#### R3：阶段R本地验证

覆盖：

- 两个bank地址0、1、638、639写读；
- front读与back写并行；
- 完整块前不显示随机内容；
- block_done只置pending；
- 活动区不翻bank；
- 帧消隐翻转后整帧只读新front；
- 多块连续到达时不出现角色错乱；
- 一拍BRAM返回和视频元数据对齐；
- V2-01/WAV/音量回归与顶层stub展开。

#### R4：阶段R TD硬门槛

用户只运行`syn_1`：

- 两个waveform bank各占1个BRAM9K；
- BRAM总数31→33；
- 日志不再报告waveform Logic DRAM；
- peak RAM不参与综合；
- DSP保持13；
- waveform存储层级不再出现约1000 LUT展开；
- 综合LUT明显低于16204，硬上限15000；
- 无错误、black box、latch、多驱动。

任一失败立即停止，只修BRAM参数/端口/TD配置，不进入阶段S，不运行`phy_1`。

### 阶段S：动态帧采样与空间/时间滤波

#### S1：动态DDA采样

每轮维护：

- `samples_est`，初始800；
- `sample_count`；
- `phase_acc`；
- `column_idx=0~639`；
- `window_peak`、`last_emitted`。

每个被采集的`audio_valid`：

1. 从最终`vol_audio_l/r`求饱和绝对值并取最大，复用V2-01压缩；
2. `window_peak=max(window_peak,current)`；
3. `phase_next=phase_acc+640`；
4. 若`phase_next>=samples_est`，写当前列窗口峰值、减去`samples_est`、推进列并清窗口；否则仅累积。

每轮完成后，若`sample_count`位于700~900，作为下一轮`samples_est`；异常时保持上一有效估计。滤波期间少量音频样本不采集，估计自动适应实际可用窗口。

帧末：

- 已形成640列时忽略少量尾样本；
- 少量缺列用`last_emitted`补齐；
- 无样本时补零；
- back的0~639每轮全部重写；
- 相位和列地址每轮重置，不跨帧累计漂移。

#### S2：空间滤波

`spatial[i]=(left+2×center+right+2)>>2`

- i=0时left=raw0；
- i=639时right=raw639；
- 邻域用滚动寄存器，确保原始值在被覆盖前已完成最后一次邻域读取；
- 不假设第三读口。

#### S3：时间滤波

`filtered[i]=(5×front[i]+11×spatial[i]+8)>>4`

- 旧帧5/16、新帧11/16；
- 只用移位加法，不新增DSP；
- 首次提交直接使用spatial。

消隐FSM按请求、计算、写回流水，每列约三拍；连同预取、补齐、排空，总预算硬限制小于3000个25MHz周期。地址639最终写回、管线排空且仍在消隐期才翻bank；若有效区提前到来，不翻bank、继续显示旧front并丢弃本轮back。

#### S4：阶段S验证与TD门槛

ModelSim覆盖800、801、802、806、807样本窗口，806/807交替1000帧无列漂移；空间/时间滤波黄金向量、边界、首帧、超时不翻转、总耗时和地址639排空。

用户再次运行`syn_1`：两个BRAM保持、DSP仍13、LUT不超过阶段R合理增量、waveform路径不成为新异常长路径。通过后进入阶段V。

### 阶段V：48px居中对称视觉与移除旧电平条

#### V1：最终布局

- 全宽x=0~639；
- 波形y=380~427；
- 中心边界y=404；
- 上半y=380~403；
- 下半y=404~427；
- y=428~431留4px；
- 字幕从y=432开始。

高度仍为0~24：

- 上半：`y>=404-h && y<=403`；
- 下半：`y>=404 && y<404+h`；
- 非零幅度但h=0时抬为1px；
- 不加额外1.5倍增益，防止中高幅长期饱和。

#### V2：最终样式

- 填充色`#5BC0BE`；
- 填充alpha13/16；
- 删除四级渐变、白色峰值线和peak RAM；
- 中心线y=404，颜色`#A8A49C`，alpha6/16；
- 填充优先于中心线；
- 插入点保持在`vout_data_base → waveform_render → video_osd_overlay`。

#### V3：删除右侧旧电平条

`video_osd_overlay.v`删除：

- `I_audio_level`端口；
- AUDIO颜色常量；
- `audio_bar_segment/audio_bar_color`；
- audio level同步寄存器；
- panel/border/bar区域和最终三个音频分支。

`top_tf_hdmi_audio.v`删除：

- `pcm_abs24`、电平/过零率换算函数；
- audio level相关wire/reg；
- 逐帧峰值/过零率统计always；
- OSD的`I_audio_level`连接。

保留最终`vol_audio_l/r + audio_valid`到HDMI与波形采样器的连接。

## 4. 验收方式

### 4.1 ModelSim

显式双bank：

- 地址0、1、638、639；
- 一拍读与标签；
- front读/back写并行；
- 角色翻转；
- 不依赖同址读写语义。

动态采样：

- 窗口800、801、802、806、807；
- 806/807交替1000帧无漂移；
- 异常估计保护；
- 每列1/2样本峰值；
- 帧边界同拍归属；
- 尾列补齐与无样本补零。

滤波与原子提交：

- 冲激、阶跃、斜坡、交替列；
- 首尾边界；
- 时间滤波与首帧；
- 每地址最终只写一次；
- 地址639写回后才提交；
- 总耗时小于3000拍；
- 有效区提前时不翻bank；
- 活动区front_sel稳定。

视觉：

- x=0/639；
- y=379/380/403/404/427/428/431/432；
- 幅度0/1/254/255；
- 低幅抬1px；
- 上下镜像；
- 填充和中心线alpha；
- RGB/VS/DE/坐标与BRAM读延迟统一；
- 行首不继承上一行x=639。

删除项与回归：

- 全工程无活跃peak RAM、`I_audio_level`、`audio_level_bar`；
- 回归V2-01、WAV两个场景、真实时钟比、数字音量、顶层stub展开；
- 不新增代码注释、隐式线网、多驱动、latch或非预期乘法器。

### 4.2 最终TD门槛

预期：

- BRAM9K=33；
- DSP=13；
- 综合LUT约13600~14500；
- 布局后LUT约14000~15200且使用率<80%；
- Slice使用率<90%，目标≤85%；
- waveform/video_clk路径不得成为负裕量关键路径；
- 全局setup不得劣于E10约−6.699ns；
- hold WNS≥0、hold违例端点0；
- 满足后才生成bitstream。

### 4.3 上板最终验收

- 波形完整位于x0~639、y380~427，围绕y404上下对称；y428~431留空，字幕不被挤压；
- 右侧旧电平条与白色峰值线完全消失；
- 青绿填充清晰，中心线低调，背景可见；
- WAV、测试音、音量变化均能驱动；静音自然收敛到中心线；小信号至少1px，大音量接近上下各24px但不长期饱和；
- 无V2-02的乱跳、半帧改写、固定错列、行首毛刺、闪烁或HDMI失锁；
- 59.52Hz下无周期性横向爬动；
- reveal/fade继续作用于波形；
- 连续运行至少30分钟；
- 图片装载、切图、轮播、方向、WAV、音量、亮度/对比度、OSD字幕、坏图与拔卡恢复无回归。

## 5. 回退点与风险

硬件稳定回退点始终为E10，V2-02仅是实验版本。

分阶段回退：

- R失败：撤回双bank管理，不把Logic DRAM恢复为正式路线；
- S失败：保留已通过BRAM门槛的双bank与原子提交，只撤回DDA/滤波；
- V失败：保留资源与稳定架构，只调整坐标/alpha/OSD删除，不恢复peak RAM或旧电平条。

主要风险：

- BRAM原语模式错误：阶段R综合硬检查；
- 不可实现多端口：每bank固定一写一读，邻域用滚动寄存器；
- 覆盖未读原始值：写回必须落后最后一次邻域读取；
- DDA估计误差：每轮相位/列地址清零，最多尾列补齐，不跨帧累计；
- 滤波超时：不翻转、保留旧front；
- 首帧随机值：front_valid前旁路，首次提交不使用旧front；
- 视频错位：所有元数据与BRAM延迟统一；
- 资源拥塞与hold：最终Slice必须低于90%，hold必须无违例；
- 当前工作区已有大量无关变化：禁止整仓reset/clean。

## 6. 任务过程记录

- 2026/10/11：用户完成V2-02综合、布局布线和上板，原功能正常、波形随音频变化，但视觉效果不美观；用户选择48px居中对称波形、字幕上方布局，并考虑移除旧电平条。
- 2026/10/11：核对最新TD报告，确认waveform/peak数组均落入Logic DRAM而非BRAM，BRAM仍31；综合LUT16204，布局后LUT16565，Slice超过90%，hold WNS−0.012ns/4端点。V2-02标记暂停实验版本并归档，E10保持稳定点。
- 2026/10/11：建立V2-03方案，冻结三阶段R/S/V路线。
- 2026/10/11 阶段R本地实现：`waveform_ram.v`改为两个显式`EG_LOGIC_BRAM` bank，加入`front_sel/front_valid/back_pending/block_accept`控制；`waveform_data.v`新增`block_accept`背压，完整back提交前暂停采集，避免覆盖；`waveform_render.v`移除peak读写通路，暂保留V2-02简单24px渲染以单因素验证资源与原子性；顶层移除`waveform_peak_ram`活跃实例并连接双bank控制。新增RTL改动未撰写代码注释。
- 2026/10/11 阶段R验证：`WAVEFORM_DATA PASS`、双bank`WAVEFORM_RAM PASS`、端到端`WAVEFORM_PATH PASS`；覆盖完整块pending、背压、活动区不翻转、帧消隐翻转、两bank交替和地址0/1/638/639。`tb_wav_player`两场景、`tb_wav_realclk`、`tb_audio_volume`全部PASS。使用临时SDRAM接口stub的完整顶层`vopt`成功，两个显式`EG_LOGIC_BRAM`实例成功装载，只有工程既有warning；stub与临时工作库已删除。
- 2026/10/11：用户完成阶段R TD `syn_1`，全部硬门槛通过：45个源文件分析成功；两个8bit waveform bank均显式落入BRAM，`u_waveform_ram`层级为11 LUT/5 REG/2 BRAM；BRAM9K由31增至33；不再出现waveform Logic DRAM；peak RAM未参与综合；DSP保持13；LATCH=0、无综合错误。综合LUT由V2-02的16204降至13826，释放2378 LUT并低于15000硬上限。综合setup WNS −7.288ns、hold WNS +0.471ns，最差路径仍在既有`ext_mem_clk/sd_card_clk`。阶段R正式通过，不运行布局布线，转入阶段S动态采样与空间/时间滤波。

- 2026/10/11 阶段S本地实现：`waveform_data.v`改为按视频帧关闭窗口，使用上一有效窗口实际样本数作为下一轮DDA分母，按窗口峰值映射640列，并在帧末补齐尾列或全零；`waveform_ram.v`在消隐期对back执行边界复制的`[1,2,1]/4`空间滤波及`old×5/16+new×11/16`时间滤波，地址639最终写回后原子翻bank。滤波采用保守多拍读取/写回，总处理约4480拍，满足消隐预算。
- 2026/10/11 阶段S验证：800、806、807样本窗口均稳定输出640列；无样本补零、补齐、空间边界、第二帧时间滤波和端到端采集→滤波→提交→读取均PASS。复查发现时间滤波旧值最初在左邻读取时锁存，已修正为中心列读取时锁存并重跑回归。`WAVEFORM_DATA PASS`、`WAVEFORM_RAM PASS`、`WAVEFORM_PATH PASS`；WAV两场景、真实时钟比、数字音量和顶层stub展开全部通过，仅有工程既有warning；临时工作库与stub已删除。
- 2026/10/11：用户完成阶段S TD `syn_1`，门槛通过：BRAM9K保持33、DSP保持13，双waveform bank仍各占1个BRAM且无Logic DRAM；综合LUT14290/19600，比阶段R增加464且远低于V2-02的16204；LATCH=0、无综合错误；hold WNS +0.471ns、无hold违例。setup WNS −7.288ns，最差路径仍在既有`ext_mem_clk/sd_card_clk`，报告未显示waveform成为异常关键路径。阶段S正式通过，进入阶段V 48px对称视觉与旧电平条移除。

- 2026/10/11 阶段V本地实现：`waveform_render.v`改为`x=0~639、y=380~427`、围绕`y=404`上下各24px镜像；非零低幅至少1px；填充使用`#5BC0BE`与13/16 alpha，中心线使用`#A8A49C`与6/16 alpha；移除四级渐变与白色峰值线。`video_osd_overlay.v`删除右侧音频电平条端口、颜色、函数、同步寄存器、区域与合成分支；顶层删除旧峰值/过零率统计wire/reg/functions/always及OSD连接，保留最终PCM到HDMI与波形采样器。
- 2026/10/11 阶段V验证：首次视觉测试因测试台在同一仿真时刻拉高`rd_valid`后立即取组合输出而误读旧背景，加入1ns delta采样延迟后`WAVEFORM_RENDER PASS`。最终`WAVEFORM_DATA`、`WAVEFORM_RAM`、`WAVEFORM_PATH`、`WAVEFORM_RENDER`、WAV两场景、真实时钟比、数字音量全部PASS；全工程搜索确认无活跃`I_audio_level/audio_level_bar/peak_ram`；使用临时SDRAM stub的完整顶层`vopt`成功，只有工程既有warning；临时库与stub已删除。
- 2026/10/11：最终快速只读复核发现空间滤波原地写回后，下一列若再从RAM读取左邻会读到已滤波值，形成方向性递归而非原始对称`[1,2,1]/4`。已改为滚动寄存器保存上一列原始center：首列left=raw0，后续left取尚未覆盖前锁存的上一原始center；RAM只读当前center/right。测试向量改为非线性伪随机列并增加地址2/127/320检查，`WAVEFORM_DATA/RAM/PATH/RENDER`全部PASS；修复后的完整顶层stub展开通过。
- 2026/10/11：用户完成最终`syn_1`，全部综合门槛通过：BRAM9K=33、DSP=13；双waveform bank共占2 BRAM，`u_waveform_ram`层级仅131 LUT/53 REG，不再出现waveform Logic DRAM；综合LUT13701/19600（69.90%），比V2-02实验版16204下降2503；REG7626；LATCH=0、无综合错误。综合setup WNS −6.302ns，hold WNS +0.471ns、无hold违例；over-quota仍只在既有`ext_mem_clk/sd_card_clk`，未显示waveform/video_clk成为异常关键路径。最终综合通过，可以由用户继续`phy_1`、bitstream与上板；上板通过前不更新使用说明、不归档、不建立新稳定点。
- 2026/10/11：用户反馈上板长期运行后波形趋同为等高蓝色块，且实心填充观感仍不佳。原因确认：跨帧同列时间滤波会把不具时间对应关系的640列逐渐平均；决定删除时间滤波，保留双BRAM、DDA、横向滤波和原子帧提交；渲染改为上下对称的连续青绿色轮廓线，中心线保留低alpha。
- 2026/10/11：连续线条渲染自检通过，覆盖上下镜像、前后列连接段、连接段边界、中心线和区域边界。初次测试误报由测试台连续请求与同步返回未隔离造成，已改为逐请求/返回测试协议后`WAVEFORM_RENDER PASS`；V2-01数据、双bank、端到端和音频回归继续通过。最终顶层需在本次时间滤波删除、线条渲染和空间滤波修复后重新综合。

- 2026/10/12：用户给出目标样式为底部统一基线的密集竖条，并再次反馈长时间运行后波形变直线。进一步核对确认最终PCM链路存在跨域错拍风险：`audio_valid/audio_left/right`在video_clk，而WAV选择与音量寄存器在audio_mclk，增益后PCM又被video_clk波形采样。已将`wav_playing`同步、WAV/测试音mux、音量按键消抖和`audio_volume_gain`全部统一到video_clk；HDMI与waveform共享同一`audio_valid + vol_audio_l/r`。WAV两场景、真实时钟比和音量回归全部PASS。
- 2026/10/12：滤波状态机异常保护修复：F_WRITE遇到video_de不再清pending/丢块，改为写完当前列后进入F_PAUSE，活动区保持front与pending，下一消隐从下一列继续。注入有效区中断的ModelSim测试通过，front不翻转、back不被新块覆盖、后续可完整提交。
- 2026/10/12：波形渲染改为统一底部基线y=427的密集竖条，区域y=384~427，2px柱+1px透明间隙，灰青色`#B7C5C8`、12/16 alpha，低幅门限amp<=2不画，最大高度44px；删除中心线、连续填充和峰值线。修复高度中间量溢出、模3不能用x低2位以及alpha权重问题后`WAVEFORM_RENDER PASS`。
- 2026/10/12：新增`tb_waveform_longrun.v`运行5000帧，front翻转5000次，5000帧抽样列全部保持非等高，`WAVEFORM_LONGRUN PASS flips=5000 nonuniform=5000`；波形数据、RAM、端到端、渲染、WAV、真实时钟比、音量回归与最终顶层stub展开均通过。临时仿真库与stub已删除。
- 2026/10/12：最终竖条修复完成：WAV/测试音mux、音量按键消抖和`audio_volume_gain`全部统一到video_clk，HDMI与waveform共享同一`audio_valid + vol_audio_l/r`；滤波遇到有效区改为F_PAUSE，写完当前列后保持pending/front，下一消隐从下一列继续；渲染改为y=427基线、最大44px、2px柱+1px间隙、灰青色`#B7C5C8`与12/16 alpha。修复高度中间量溢出、模3译码和alpha权重后，波形/音频测试与顶层展开全部通过。
- 2026/10/12：新增5000帧长测，`WAVEFORM_LONGRUN PASS flips=5000 nonuniform=5000`；注入F_WRITE有效区中断测试通过，front不翻转、pending保留并在下一消隐完整提交。当前等待用户重新执行`syn_1`。本次同域音频、滤波暂停恢复和竖条渲染均发生在旧报告之后，必须重新核对BRAM33、DSP13、LUT、video_clk/waveform路径和综合hold；通过后再运行phy/bitstream与至少30分钟上板长测。
- 2026/10/12：此前上板曾出现一次数码管B类诊断、主画面黑屏而仅剩条纹；B类含义为源数据已完成但SDRAM帧写完成事件未返回。用户确认软复位即可恢复，重新上电未复现，属于极小概率既有时序边界事件，决定暂不修改SDRAM/FIFO写帧链。本轮仅登记为已知风险，不作为竖条波形验收阻塞项；若后续复现频率升高，再单独建立时序/CDC修复任务。

- 2026/10/12：用户确认即使多轮修复后，波形长时间仍会固定高度，决定暂停该问题并继续V2任务顺序。V2-03当前源码保留，5000帧仿真结果和TD/上板事实保留，但任务不标记通过、不建立新稳定点；E10继续作为硬件回退点。若后续重启，优先从真实上板音频样本/提交统计取证，而不是继续凭仿真调整视觉。

V2-03暂停期间不更新面向使用者的波形完成说明；当前界面与已知限制在进度台账保留。`Project/doc/工程交互使用说明文档.md`：删除右侧电平条说明，增加全宽48px对称波形、中心线、音量和静音响应及演示步骤。是否建立新稳定版本由用户决定，不自动命名E11。

- 2026/10/15：最终竖条版随 10/12 15:31 phy_1 bitstream 上板，观察清单①~⑤全部通过：底部竖条随音乐跳动、静音塌回、10 分钟长稳未复现"柱高固定"、无撕裂遮挡、不挡 OSD，E10 全部功能无回归；phy_1 LUT 14990/REG 8441/BRAM9K 34/DSP 13、HWNS +0.019ns、SWNS −6.699ns，波形存储落 BRAM。V2-03 主体验收通过并随 E11 转正；4.3 节"连续运行至少 30 分钟"判据本次仅覆盖 10 分钟，30 分钟长测保留待补，不下调判据。详见台账 5.26。
