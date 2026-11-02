# EG4S20 咖啡厅音乐菜单（木与豆咖啡）

> 仓库地址：https://github.com/Power-age/EG4S20-CafeMusicMenu

基于安路（Anlogic）EG4S20BG256 的**店内音乐电子菜单**：一块 FPGA 完成从 TF 卡读取、图片缩放、中文叠加、音频播放到 HDMI 输出的全部工作，无处理器、无操作系统。

关键词：**真实 DFT 音频可视化 · 帧边界原子切换 · 纯硬件 OSD 交互闭环**

## 功能

| 分类 | 功能 |
|---|---|
| 显示 | **4 页海报**（1280×960、1280×960、1280×720、400×400 方图）常驻 SDRAM 四个分区，按页记录宽高与居中偏移，等比缩放自动补黑边；640×480@60 HDMI 输出 |
| 翻页 | 只改分区号、在帧消隐边界提交，**零加载、无撕裂**；支持手动翻页与自动轮播 |
| 中文角标 | 左上角 1bit 掩膜中文标签（4 页各一条），翻页时左侧滑入；**设置面板打开时仍显示**，放大约束下隐藏 |
| 转场 | 揭幕扫入（WIPE）/ 黑场淡入淡出（FADE），均在帧边界提交 |
| 局部放大 | 2× 双线性，**放大窗口按页对准商品**（封面不放大），两个按键功能一致，放大中翻页自动退出 |
| 音频 | TF 卡裸 PCM（48kHz/16bit/单声道）流式播放；无曲目时切内置测试音（DDS 直出，音高对齐 DFT 频点）；±10 秒快进快退 |
| 频谱 | 1024 点 Q15 定点 DFT、40 段对数分箱，跨频平滑 + 峰值保持，**紧贴画面最底行**渲染 |
| 交互 | 7 项设置面板（音量/亮度/对比度/转场/自动轮播/周期/TONE）、切歌、音量 16 档（SW2 预设） |
| OSD | 右上角「歌名 + 剩余时间」、左上角中文角标、中央设置面板，逐像素叠加不破坏底图 |

## 目录结构

```
src/
  user_source/hdl_source/         Verilog 源码（顶层 top_tf_hdmi_audio.v）
    SD/                           SD 卡 / FAT32 / BMP 解码 / 帧缓存 / WAV 播放
    python/                       素材与 ROM 生成脚本
    hdmi1.4b_transmitter_core/    HDMI 发送器封装（加密 IP）
    ip/                           时钟 / FIFO IP 封装
  user_source/constraints_source/ 引脚约束、时序约束（分域 SDC）
  td_project/                     TD 工程（.al）与两个 run 的工程/配置
sim/                              测试台（tb_*.v）与自动化脚本（loop.ps1、seed_sweep.ps1）
doc/                              项目方案、进度、交互说明、作品简介
```

## 构建

1. 安装安路 TD 5.6.2；
2. 打开 `src/td_project/HDMI1.4b_Transmitter_v1.0.al`，或使用命令行流程；
3. **布局种子写在 `.../phy_1/settings.cfg` 的 `set phyWildParams {place seed N}`**（当前最优 `seed 5`）。注意：用 TD GUI 重建 run 会把这一行冲掉，重新布线前务必确认它还在；
4. 批处理流程：`powershell -ExecutionPolicy Bypass -File sim/loop.ps1 -Seed 5`。
   流程在 `route` 后插入 `fix_hold`，并设**时序门禁**：setup 与 hold 全部 ≥0 才允许更新交付件。

## 关键指标（定稿版，seed 5）

| 项 | 值 |
|---|---|
| 器件 | EG4S20BG256（TD 5.6.2）|
| slices | **87.74%**（2497 / 2846）|
| LUT / REG | 约 9.4k / 8.8k |
| BRAM9K / BRAM32K / DSP | 15 / 64、0 / 16、11 / 29 |
| `sd_card_clk`（75MHz） | setup **+0.320 ns** / hold **+0.014 ns** |
| `video_clk`（25MHz） | setup **+11.732 ns** / hold **+0.003 ns** |
| `ext_mem_clk`（125MHz） | setup **+0.933 ns** / hold **+0.021 ns** |
| 违例端点 | **setup + hold 合计 0（九个时钟域全绿）** |
| 固化 | QSPI Flash 固化，上电自启 |
| 交付 MD5 | `614270A8D5D7905C2B40E89A5E488F72` |

## 已知限制

- HDMI 输出固定 640×480@60，不按显示器协商分辨率；
- 放大只提供 2×（1.5× 等非整数倍需重做任意比例缩放器，未实现）；
- 快退需回簇链头重走，约 1~3 秒等待（FAT32 簇链单向）；
- 运行中更换为另一张卡后需按 KEY1 复位（固件启动时缓存 FAT32 目录，不会自动重扫）；
- 音频底噪取决于显示器功放（`VOLUME=0` 时仍有底噪即为此因）；
- 素材需放在 TF 卡根目录、24bit 无压缩 BMP（`PIC1~PIC4.BMP`）与裸 PCM（`TRACK01~03.RAW`）。

## 文档

- `doc/项目方案.md` — 定位、参数、任务清单、决策纪要
- `doc/项目进度.md` — 逐版构建台账（最新在最前）
- `doc/工程交互使用说明文档.md` — 按键、OSD、演示脚本、故障排查
- `doc/作品简介.docx` — 参赛用简介
- 技术报告与交付素材见竞赛提交材料

## 许可

代码以 [MIT License](LICENSE) 发布。

工程中引用的 HDMI 发送器核、SDRAM 初始化核为芯片厂商（安路科技）随 TD 工具提供的加密 IP，版权归原厂，不在本仓库许可范围内。
