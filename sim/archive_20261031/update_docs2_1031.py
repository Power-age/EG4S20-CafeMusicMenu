import io

BASE = r"D:\AAA_University\Anlu\Project"

# ---------- 项目方案.md：功能表 & 参数 & 目录说明 ----------
p = BASE + r"\doc\项目方案.md"
s = io.open(p, "r", encoding="utf-8").read()

reps = [
    # 功能表：局部放大定稿 2x
    ("| 新增 | **局部放大 2×（双线性，左/右单卡）** | ✅ E19.9 |",
     "| 新增 | **局部放大 2×（按页对准商品；封面不放大；两键统一；放大中切页自动退出）** | ✅ 2026-10-31 |"),
    # 参数表：时序行补充 hold 口径
    ("| 时序 | `sd_card +0.243` / `video +11.341` / `ext_mem +0.749` → **三域 0 违例**（2026-10-31 回退版） |",
     "| 时序 | **setup 全绿**：`sd +0.24` / `video +11.4` / `ext_mem +0.71`；**hold 残差 −4~20ps**（BRAM 地址短路径，已接受，见 §7.4）|"),
    # 参数表：面积行
    ("| 面积 | slices ≈ **91.51%**（2026-10-31 回退 4 bank 后）；LUT ≈ 10.0k、REG ≈ 9.1k；BRAM9K 15/64、BRAM32K 0 |",
     "| 面积 | slices ≈ **90.98%**（定稿 `DD3ACA48`）；LUT ≈ 10.0k、REG ≈ 9.1k；BRAM9K 15/64、BRAM32K 0 |"),
]

n = 0
for a, b in reps:
    if a in s:
        s = s.replace(a, b)
        n += 1

# 追加"项目文件结构"章节（放在 §4 之前）
anchor = "## 4. 交付与烧录"
tree = """## 3.2 项目文件结构（2026-10-31 整理）

```
Project\\
├─ src\\user_source\\hdl_source\\      RTL 源码（top_tf_hdmi_audio.v 为顶层）
├─ src\\user_source\\constraints_source\\  timing.sdc
├─ src\\td_project\\..._Runs\\best_result\\  交付 bit（仅"过门禁"版本会同步到这里）
├─ doc\\                              设计文档
│   ├─ 项目方案.md                    主文档（定位/功能/参数/结构/任务/时序口径）
│   ├─ 项目进度.md                    台账（只追加）
│   ├─ Anlu.md                        协作规则与工程经验
│   ├─ 工程交互使用说明文档.md / 作品简介.docx / 赛题文本 / 选题指南
│   ├─ TF卡\\                          卡内素材（1_交付_写卡用 为最终交付）
│   └─ archive\\<日期>\\                历史方案与阶段文档
└─ sim\\                              仿真、构建与工具脚本
    ├─ loop.ps1                       一键构建 + 时序门禁 + 烧录
    ├─ DefaultFlow_hold.tcl           TD 流程补丁（route 后 fix_hold）
    ├─ make_badge_mask.py             中文角标掩膜生成
    ├─ make_text_mask.py              文字掩膜渲染
    ├─ make_delivery_bmps.py          PNG→BMP 交付
    ├─ tb_zoom.v                      放大部分映射仿真
    ├─ archive_20261031\\              一次性脚本归档
    └─ backups\\                       源码与固件回退点
```
"""
if anchor in s and "## 3.2 项目文件结构" not in s:
    s = s.replace(anchor, tree + "\n" + anchor)

io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("项目方案.md: 替换 %d 处，结构章节 %s" % (n, "已加" if "## 3.2 项目文件结构" in s else "未加"))

# ---------- 项目进度.md：追加清理与归档记录 ----------
p2 = BASE + r"\doc\项目进度.md"
t = io.open(p2, "r", encoding="utf-8").read()
entry = """### 2026-10-31 09:50 工程目录清理 + 全量文档归档

- **sim 瘦身**：121.4 MB / 540 文件 → **33.3 MB / 181 文件**（回收约 88 MB）
  - 删除 `diag_covers/`（63.6 MB 海报探索诊断图，结论已进文档）
  - 8 个旧备份目录压缩为 `sim/backups/old_backups_20261031.zip`（30.4 MB）
  - 删除 iverilog 工作目录 `work_geom` / `work_up480`；构建日志只留最近 5 个
- **新增** `sim/README.md`：现役工具 / 归档 / 命名约定（含"通过的 bit 要另存 backups"规则）
- **重写** `doc/TF卡/README.md`：按 4 页定稿描述交付物 + 素材规格 + **文字安全区（顶 40px / 底 24px）**
- **更新** `doc/项目方案.md`：功能表（放大 2× 定稿口径）、参数表（面积 90.98%、时序 setup 全绿 + hold 残差）、新增 §3.2 项目文件结构
- **归档** `doc/Anlu_小步推进方案_局部放大.md` → `doc/archive/20261031/`（带结论头）

"""
t = entry + t
io.open(p2, "w", encoding="utf-8", newline="\n").write(t)
print("项目进度.md: 已追加 09:50 条目")
