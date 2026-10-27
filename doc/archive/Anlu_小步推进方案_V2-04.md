# Anlu 小步推进方案 V2-04：固定编号裸PCM多曲目播放

## 1. 背景与目标

V2-03长时间波形固定问题按用户决定暂停并归档，不阻塞后续任务；当前源码保留，E10继续作为硬件回退基线。

V2-04目标：在FAT32根目录识别最多16首`TRACK01.RAW`~`TRACK16.RAW`，按编号顺序播放，支持自动轮播与音量模式长按前后曲。文件格式固定为48kHz、16bit signed、小端、单声道、无头裸PCM。

本任务分三阶段：A扫描与列表；B播放器真正完成与安全切歌；C按键/CDC/最终集成。阶段A未通过TD资源门槛前，不修改播放器与交互。

本任务不支持标准RIFF/WAV、任意文件名、长文件名、子目录、随机播放、单曲循环设置，不复制scanner、不增加第四个SD仲裁源，不继续处理V2-03波形问题，不新增代码注释。

## 2. 当前代码事实

- `fat32_volume_scanner.v`已支持MBR/BPB、根目录跨扇区/跨簇、PIC1~4和固定MUSIC.WAV；music为可选资源。
- 根目录FAT扇区地址使用`cluster>>7`正确，但扇区内偏移错误地使用低3位，应使用低7位×4。
- `sd_card_bmp.v`已有scanner、图片chain、音频chain和SCAN>PIC>WAV三源仲裁；WAV只有all_resident后允许，不应新增仲裁源。
- `wav_stream_player.v`当前`stream_end`表示SD源读完，不代表缓冲最后样本播放完；play_enable高电平模型不支持安全切歌。
- 当前音频格式虽扩展名为WAV，实为48kHz/16bit/单声道/小端裸PCM。
- key1/key2在切图模式用于切图/自动图片轮播，在音量模式用于音量−/＋；`key_longshort.v`已有测试但顶层未用。
- 最新资源约LUT13.5k、BRAM33、DSP13，Slice约80%，setup仍有既有深负裕量；不能复制scanner或使用宽寄存器数组。

## 3. 改动步骤

### 阶段A：scanner与曲目列表

A1. 单因素修复根目录FAT偏移：使用`root_cluster_cur[6:0]×4`的9bit偏移；扩展scanner测试覆盖低7位大于7和跨FAT扇区，图片/MUSIC回归不变。

A2. 扩展现有scanner输出：`track_push/index/name/cluster/size`。只匹配`TRACK01 `~`TRACK16 `和`RAW`；排除LFN/目录/卷标/删除项；簇合法、大小非零且偶数。重复编号覆盖槽但不重复计数；曲目列表为空仍允许图片扫描成功。

A3. 新增`track_list.v`：一个显式BRAM9K，物理按字节存储，每槽19字节，16槽。scanner push后串行19拍写入；扫描完成后lookup串行读完整描述符。维护valid_mask和track_count，扫描重启只清有效状态。

A4. 阶段A只验证扫描和列表，暂保留旧MUSIC单曲播放。ModelSim覆盖乱序、缺洞、0/1/16首、跨簇/跨FAT、非法名/属性/大小、重复编号和二次扫描。用户只跑syn_1：BRAM33→34、DSP13、LUT<15000、无latch/black box/多驱动；未通过不进入B。

### 阶段B：player与controller

B1. `wav_stream_player.v`增加play_start/play_stop/file_size_bytes/play_busy/source_done/play_finish/play_error。start锁存精确字节数，扇区数向上取整；最后扇区只接受声明有效字节。start/stop用toggle与video读域flush握手，清指针/Gray/计数/半字节状态。

B2. source_done仅表示有效字节进入缓冲；play_finish必须在读域最后真实样本消费后通过toggle回SD域。预填至少256样本，短文件source_done例外；切歌64个sample_tick静音保护；下溢输出零且不消费不存在数据。

B3. 新增`track_controller.v`：EMPTY→SELECT→LOOKUP→STOP→WAIT_PLAYER_STOP→WAIT_SECTOR_IDLE→CHAIN_LOAD→SETTLE→PLAYER_START→RUN→ERROR_SELECT。安全条件`wav_sector_idle=!wav_chain_m_req && !(grant_valid&&grant==WAV)`。优先级error>人工下一首>人工上一首>自动finish。坏曲置failed_mask；全坏停止并回测试音；空列表测试音；单曲自动重播。

B4. 继续复用单个WAV chain和三源仲裁。每次新曲先stop/flush，等旧物理扇区结束，再load_start新簇，至少下一拍player start。

### 阶段C：按键/CDC与集成

C1. video_clk域使用`key_longshort`：音量模式短按松手调音量，600ms长按上一/下一首，长按松手不补短按；模式切换按住时需先松手。切图模式不变。

C2. 长按命令用稳定cmd_data+req toggle邮箱到SD域，ack toggle返回；ack前data保持，重复长按只保留一个pending。

C3. 列表活动时RAW路径持续选中，预填/切歌/错误阶段输出零，不短暂切回测试音；空列表/全坏才回测试音。输出当前name/index供V2-08使用。

## 4. 验收方式

阶段A测试：高根簇FAT偏移、跨簇目录、乱序16/02/10/01仍按编号槽；缺洞、0/1/16首；TRACK00/17、小写、错误扩展、LFN/目录/卷标/删除、零长/奇长、重复编号、二次扫描。

阶段B测试：文件大小2/510/512/514/1024/1026、大文件回绕；有效尾字节、不播放填充；source_done早于play_finish；最后样本后finish；stop在各状态；chain error/timeout；首尾回绕、坏曲跳过、全坏停止、空列表和单曲循环。

阶段C测试：短按只一档、长按只切歌、松手不补短按、模式切换无误触；25/100MHz随机相位req/ack；快速长按不丢命令；最终音源不串测试音。

全量回归scanner/chain/arbiter/WAV/真实时钟/key_longshort/volume/waveform/resident/装载/拔卡和顶层stub。

TD门槛：A阶段BRAM34、DSP13、LUT<15000；B/C阶段BRAM仍34、DSP13、LUT<15500。最终phy要求布局后LUT<80%、Slice<90%、hold WNS≥0且0端点；V2-04路径不得成为最差setup路径。通过后才bitstream。

上板组合：0首、1首、缺洞、乱序复制、16首、非512对齐、碎片、坏链/截断、多坏曲、短曲快速轮播。验证顺序、短长按、尾音完整、无填充噪声、无旧残样/测试音串入、坏曲跳过和30分钟稳定回归。

## 5. 回退点与风险

硬件回退E10。A失败只撤track流/list，保留已证明的FAT偏移修复；B失败回A并恢复旧单曲player对照，不保留错误完成语义；C失败保留scanner/list/player/controller，只撤交互/CDC。上板异常先回E10 bitstream，不整仓reset/clean。

主要风险：stream_end误作play_finish；非512尾部噪声；切歌时旧物理扇区未结束；缓冲flush跨域；按键短长按冲突；scanner逻辑加重setup；宽列表未落BRAM；坏曲无限循环；当前setup既有深负裕量。

## 6. 任务过程记录

- 2026/10/12：用户决定暂停V2-03长期波形固定问题并继续后续任务；V2-03归档，E10保持稳定点。
- 2026/10/12：用户冻结V2-04交互与文件口径：音量模式key1/key2短按音量−/＋，长按上一/下一首；文件名TRACK01.RAW~TRACK16.RAW，格式48kHz/16bit signed/小端/单声道/无头裸PCM，按编号播放。
- 2026/10/12：建立本方案。当前仅进入阶段A，player/controller/按键暂不修改。
- 2026/10/12 阶段A1：修正根目录FAT表项偏移，由错误低3位改为低7位×4并扩为9bit；`tb_scanner_root`回归通过，PIC1~4与旧MUSIC扫描无回归。
- 2026/10/12 阶段A2：扩展现有scanner，固定识别TRACK01.RAW~TRACK16.RAW并输出单周期track_push/index/name/cluster/size；乱序目录中的01/02/10/16正确映射到编号槽，旧资源无回归。
- 2026/10/12 阶段A3：新增`track_list.v`，单个显式BRAM9K按每槽19字节保存16槽描述符；独立行为模型测试覆盖乱序写入、mask/count、按索引读回、重复编号覆盖不重复计数和clear重建，`TRACK_LIST PASS`。
- 2026/10/12：track list已接入`sd_card_bmp.v`，lookup暂关闭，播放链保持旧MUSIC单曲。scanner/list、chain、SD仲裁回归及使用临时SDRAM stub的完整顶层展开均通过；新增`track_list`和scanner端口成功装载，仅有工程既有warning。
- 2026/10/12：首次阶段A TD综合报MSlice 5049>4900。报告定位track_list正确落入1 BRAM且仅127 LUT/167 REG，真正膨胀的是scanner由约1333 LUT/1253 REG增至4522 LUT/4646 REG，总LUT16920。根因为修正FAT偏移后使用9bit动态`le32(fat_byte_off)`索引512字节sector_buffer，导致整扇区缓存和大mux无法裁剪。
- 2026/10/12：单因素资源修复：根FAT扇区不再写入sector_buffer，发请求前锁存9bit目标偏移，字节流经过时只捕获目标4字节到32bit寄存器，sector_done后直接解析；保留其他固定索引缓存。scanner/list回归与完整顶层展开通过。
- 2026/10/12：用户重跑阶段A`syn_1`，资源门槛全部通过：scanner恢复为1223 LUT/1304 REG；track list为128 LUT/167 REG/1 BRAM；总LUT13618、REG7813、BRAM34、DSP13、LATCH=0、无综合错误，MSlice超限消失。综合setup WNS−7.288ns、hold WNS+0.471ns，新增sd_card_clk动态15级大mux路径消失。阶段A正式通过。
- 2026/10/12 阶段B1：重构`wav_stream_player.v`为显式play_start/play_stop/file_size/play_busy/source_done/play_finish/play_error；指针扩为带回绕位，start/stop使用flush toggle握手，最后非512对齐扇区只接受声明字节，play_finish在最后真实样本消费后产生。独立测试覆盖2/510/512/514/1026字节和中途stop，`WAV_PLAYER_V2 PASS`。
- 2026/10/12 阶段B2：新增`track_controller.v`，实现空列表、最小编号启动、前后有效槽、首尾回绕、自动finish下一首、坏曲failed mask、安全stop→sector idle→chain reload→player start。`TRACK_CONTROLLER PASS`。
- 2026/10/12：track list lookup、controller、现有WAV chain和新player已接入`sd_card_bmp.v`，手动cmd暂为0；列表活动期间保持RAW音源，自动播放和坏曲跳过已接线。scanner/list/controller/player独立测试、波形/音量回归及完整顶层stub展开全部通过，仅有工程既有warning。
- 2026/10/12：首次阶段B综合报`track_controller.v` non-constant loop count limit 200 exceeded。根因是next/prev/first有效槽函数用for循环并修改循环变量提前退出，TD视为运行时非恒定循环。已替换为固定16级if/else优先选择，4bit加减自然回绕，文件中无for/while残留；`TRACK_CONTROLLER PASS`且完整顶层展开通过。
- 2026/10/12：用户重跑阶段B`syn_1`通过：LUT14317、REG8187、BRAM34、DSP13、LATCH=0、无综合错误；track list保持1 BRAM，WAV缓冲保持8 BRAM；综合setup WNS−6.326ns、hold WNS+0.471ns，新增controller/player未成为最差路径。阶段B正式通过。
- 2026/10/12 阶段C：`key_longshort.v`参数化时钟并扩重复计数器到24bit；top在video_clk域用短按松手调音量、长按生成曲目命令，命令通过稳定data+req/ack toggle邮箱送SD域并形成单拍prev/next。`KEY_LONGSHORT TEST PASS`、`TRACK_CMD_CDC PASS`，完整顶层展开通过。
- 2026/10/12：使用说明已同步为TRACK01~16.RAW、裸PCM格式、短按音量/长按切歌、编号自动轮播和空列表测试音。用户完成最终`syn_1`：48个源文件分析成功，LUT14625/19600、REG8330/19600、BRAM9K 34/64、DSP13/29；track list占1 BRAM，WAV缓冲仍占8 BRAM，LATCH=0，报告未见综合错误或黑盒。综合setup WNS −7.288ns、hold WNS +0.471ns且无hold违例；`gate.qor`列出的over-quota路径仍在sd_card_clk/ext_mem_clk，不能据此认定全局setup已收敛。综合资源门槛通过；尚未核对`phy_1`、bitstream和上板结果，V2-04仍为待验收。
- 2026/10/12 补充 V2-04 验收素材准备步骤：现有 `Project/src/user_source/hdl_source/python/wav_to_pcm.py` 第 11 行使用 `wave.open`，只接受 PCM WAV，且第 56~58 行补齐 512 字节、用法文字仍指向旧 `MUSIC.WAV`。用户要求另做可处理 FFmpeg 支持编码的 WAV 转换脚本。新增独立 PC 脚本（不改旧脚本/RTL），用 FFmpeg 将输入 WAV 转为 48kHz/16bit signed little-endian/单声道无头 RAW；输出命名由用户指定为 `TRACK01.RAW` 等，失败不覆盖原文件。验收脚本命令行校验、缺少 FFmpeg、输入/输出错误和输出参数；若本机无 FFmpeg，必须如实注明实测转换未执行。此项只为现有 V2-04 准备测试曲目，不改变 TD 门槛或当前待验收状态。
- 2026/10/12 完成辅助脚本 `Project/src/user_source/hdl_source/python/wav_to_track_raw.py`，使用外部 FFmpeg 解码并输出固定 48kHz/16bit signed little-endian/单声道无头 RAW，只允许 TRACK01~16.RAW 输出名；通过临时文件避免失败时留下目标文件，拒绝覆盖已有文件。`Project/sim/test_wav_to_track_raw.py` 五项单测全部通过（参数/输出、缺少FFmpeg、目标保护、非法名、失败清理），`--help` 可运行。当时环境 PATH 中无 FFmpeg，未对真实编码 WAV 作端到端转换；使用说明已同步安装要求及两首文件的运行示例。辅助工具完成不等于 V2-04 上板验收，仍待用户完成 TD phy/bitstream/上板。
- 2026/10/12 验收卡素材实装：只读确认 TF 卡文件系统已为 FAT32，根目录保留 PIC1~4.bmp、MUSIC.WAV；原 MUSIC.WAV 无 RIFF 头，28,792,320 字节（若按 48kHz/16bit/单声道解释约 299.92 秒），其实际采样率无法从无头文件独立证明。未格式化或删除任何原文件，复制为根目录 TRACK01.RAW，SHA-256 与 MUSIC.WAV 完全一致（0180676617bebf08417affe5d4d8fcfbfba6a2edd18e9cca3dc2094dfe880dff）。另用临时安装的 FFmpeg 7.1 将 `Project/doc/bmp/Test.m4a`（AAC LC、48kHz 单声道、约 12.12 秒）转换为根目录 TRACK02.RAW（1,163,264 字节，约 12.117 秒，SHA-256 3baed3081ec21ba89d3787ff6de53c466c8959cb5429147fd4815a5c2bc61b58）。两首均为偶数字节，第一首原样复制、第二首显式输出 pcm_s16le/f=s16le。旧 MUSIC.WAV 留作备份、V2-04 扫描器只识别 TRACK 名称；卡上素材准备完成，TD phy/bitstream/上板仍待用户执行。
- 2026/10/12：用户反馈本版上板测试通过并要求继续。已收到的明确事实是双曲目测试通过；未收到最终 `phy_1` 资源/时序数字及 0/1/16 首、坏链、30 分钟等完整边界验收记录，不能将这些项目记为已验证。V2-04 功能主路径上板通过，完整冻结判据仍待补证；按用户继续推进的指令转入 V2-05。本方案归档，E10 仍是有完整回退证据的基线。
- 2026/10/15：用户完成完整上板验收（观察清单①~⑤）：TRACK01 播放、TRACK02 播完自动接续（编号回绕循环）、音量模式长按 key2/key1 600ms 切下一首/上一首、120ms 重复、短按音量、切歌不爆音、10 分钟无回归；phy_1 数据已核对（LUT 14990/REG 8441/BRAM9K 34/DSP 13、HWNS +0.019ns、SWNS −6.699ns）。V2-04 主路径随 E11 转正；第 65 行上板组合判据中的 0 首、1 首、16 首、缺洞、乱序复制、非 512 对齐、碎片、坏链/截断、多坏曲、短曲快速轮播、30 分钟稳定回归仍未测，保留为待补，不虚构通过。详见台账 5.26。
