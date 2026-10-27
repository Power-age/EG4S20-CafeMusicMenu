# EG4S20 咖啡厅音乐菜单

基于安路（Anlogic）EG4S20BG256 的**店内音乐电子菜单**：一块 FPGA 完成从 TF 卡读取、图片缩放、中文叠加、音频播放到 HDMI 输出的全部工作，无处理器、无操作系统。

关键词：**换卡即换内容 · 单芯片全链路 · 片内音画同步**

## 功能

| 分类 | 功能 |
|---|---|
| 显示 | 四页菜单常驻 SDRAM 四个 bank，翻页零加载延迟；640×480@60 HDMI 输出 |
| 转场 | 揭幕扫入（WIPE）/ 黑场淡入淡出（FADE） |
| 中文叠加 | 商品名 / 两行介绍 / 价格由卡内 1bit mask 合成 ROM，FPGA 实时叠加，翻页后两侧逐像素滑入（等转场结束才启动） |
| 局部放大 | 长按 KEY3 放大左卡、长按 KEY4 放大右卡，2× 双线性，放大时卡内文字自动隐藏 |
| 音频 | TF 卡裸 PCM（48kHz/16bit/单声道）流式播放；无曲目时切内置测试音（DDS 直出，音高对齐 DFT 频点） |
| 频谱 | 1024 点分块 DFT、40 段对数分箱，片内音频直采；SW1/SW4 切换强调档位 |
| 交互 | 7 项设置面板（音量/亮度/对比度/转场/自动轮播/周期/TONE）、切歌、快进快退 ±10s |
| OSD | 右上角「歌名 + 剩余时间」、左上角「PAGE n/4」 |

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

## 关键指标（seed 5，当前交付版本）

| 项 | 值 |
|---|---|
| 器件 | EG4S20BG256 |
| slices | 95.91% |
| REG / LUT | 9131 / 10499 |
| `video_clk` | +11.340 ns |
| `ext_mem_clk`（125MHz 帧缓存） | **+0.101 ns，0 违例** |
| `sd_card_clk`（100MHz） | −0.812 ns |
| 黑盒 / BRAM 超限 | 0 / 无 |

## 已知限制

- HDMI 输出固定 640×480@60，不按显示器协商分辨率；素材侧按目标显示器做 4:3 排版 + 横向预压缩 1/1.28，适配 1024×600 屏；
- 卡上四张图为同一比例（1280×960），因此不演示"居中黑边"；显示几何为全局一份，混尺寸素材需先补每 bank 几何表；
- 快退需回簇链头重走，约 1~3 秒等待（FAT32 簇链单向）；
- 音频底噪取决于显示器功放（`VOLUME=0` 时送数字全零仍有底噪即为此因）。

## 文档

- `doc/项目方案.md` — 定位、参数、任务清单、决策纪要
- `doc/项目进度.md` — 逐版构建台账（最新在最前）
- `doc/工程交互使用说明文档.md` — 按键、OSD、演示脚本、故障排查
- `doc/作品简介.docx` — 参赛用简介
