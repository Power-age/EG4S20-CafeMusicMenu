import io, os

BASE = r"D:\AAA_University\Anlu\Project"

# ---------------- 1) TF卡 README 重写（4 页定稿） ----------------
readme = """# TF 卡素材目录说明（2026-10-31 定稿：4 页生效）

本目录是"店内音乐电子菜单"的全部卡内素材与制作过程文件。按**用途**分 5 层。

## 1_交付_写卡用（最终交付物，直接拷进 TF 卡根目录）

| 文件 | 内容 | 分辨率 | 屏幕上 |
|---|---|---|---|
| `PIC1.BMP` | 封面（木与豆咖啡 / WOOD & BEAN / 每日现磨）| 1280×960（4:3）| 铺满全屏 |
| `PIC2.BMP` | 手冲埃塞俄比亚 ¥28 | 1280×960（4:3）| 铺满 |
| `PIC3.BMP` | 经典卡布奇诺 ¥26 | 1280×720（16:9）| 上下黑边 |
| `PIC4.BMP` | 抹茶拿铁 ¥30 | 1024×1024（1:1）| 左右黑边 |
| `TRACK01~03.RAW` | 三首曲目 | 48kHz/16bit/单声道裸 PCM | — |

> 固件只识别 `PIC1~PIC4`（4 bank），`PIC5` 及以后会被忽略；建议卡上只放这 4 张。

## 2_海报工程

- `有字版/`：GPT 生成的成品海报（`cover_new` / `p2_shouchong_new` / `p4_matcha_new` 为 2026-10-31 定稿版）；
- `无字版/`：同版式无文字底图（备用）；
- `预览图/`：640×480 观感预览。

## 3_素材源文件

- `音频源/`：8 首 mp3 原始曲目；
- `门店照片/`：封面用门店原图；
- `旧菜单图/`：历代菜单页与成品（仅留档）。

## 4_历史与测试

- `八页测试/`：早期占位图；
- `坏图/`：解析失败样本；
- `字幕掩膜_废弃/`：旧点阵字幕 BIN（固件已不用）。

## 5_工具脚本

- `convert/`：图片转 BMP、安全写卡等脚本。

## 素材规格与安全区（重要）

| 项 | 要求 |
|---|---|
| 格式 | BMP，24bit，无压缩 |
| 尺寸 | 宽、高均 **≥ 640×480**（更小的图会走上采样通路，该通路已按规格关闭）|
| 比例 | 任意（FPGA 等比缩放 + 自动留黑边）|
| **文字安全区** | 顶部 40px（≈8%）、底部 24px（≈5%）**不放文字**；背景照片/色块可以铺满 |
| 原因 | 顶部有中文角标，底部有频谱条（贴最后一行，高约 63px，仅压背景） |
"""
io.open(os.path.join(BASE, "doc", "TF卡", "README.md"), "w", encoding="utf-8", newline="\n").write(readme)
print("已更新 doc/TF卡/README.md")

# ---------------- 2) sim/README.md 新建 ----------------
simreadme = """# sim 目录说明（2026-10-31 整理）

## 现役工具（勿删）

| 文件 | 用途 |
|---|---|
| `loop.ps1` | 一键构建：综合 → 布线 → 时序门禁（**setup 与 hold 全部 ≥0** 才同步 `best_result`）→ 烧录 |
| `DefaultFlow_hold.tcl` | TD 流程补丁（`route` 后无条件 `fix_hold`，默认流程从不修 hold） |
| `make_badge_mask.py` | 生成左上中文角标的 1bit 掩膜 `txt_all.mif`（4 页各一条） |
| `make_text_mask.py` | 通用文字掩膜渲染（4× 超采样 + 边缘 Bayer 抖动） |
| `make_delivery_bmps.py` | 海报 PNG → 交付 BMP（按页缩放） |
| `tb_zoom.v` | 局部放大映射仿真（`iverilog -DZOOM_SIM`），1.5× 尝试的验证工装 |
| `burn_jtag.tcl` | JTAG 烧录脚本 |

## 归档（只读）

- `archive_20261031/`：2026-10-31 一次性脚本（补丁、探针、海报合成、分析脚本）
- `backups/`：关键源码与固件回退点
  - `bit_2x_DD3ACA48_20261031.bit`：**定稿固件**
  - `top_4bank_*.v` / `sd_card_bmp_4bank_*.v` / `mask_overlay_4096_*.v` / `video_zoom_2x_*.v`：4 bank 基线源码
  - `old_backups_20261031.zip`：更早的实验恢复点（压缩）

## 约定

1. 新测试台命名 `tb_<模块>.v`，仿真工作目录用完即删（不要留在 sim 根）；
2. 一次性脚本放 `archive_<日期>/`；
3. 每次构建后把通过的 bit 复制一份到 `backups/bit_<主题>_<md5前8位>.bit`。
"""
io.open(os.path.join(BASE, "sim", "README.md"), "w", encoding="utf-8", newline="\n").write(simreadme)
print("已新建 sim/README.md")
