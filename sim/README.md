# sim 目录说明（2026-10-31 整理）

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
