import io

BASE = r"D:\AAA_University\Anlu\Project"

# ---------------- 项目进度.md ----------------
p = BASE + r"\doc\项目进度.md"
t = io.open(p, "r", encoding="utf-8").read()
entry = """### 2026-10-31 13:35 **换卡重写 + 角标不再被设置面板遮挡（上板验证通过，定稿）**

- **固件**：**`614270A8D5D7905C2B40E89A5E488F72`**（已烧录并实测通过）
  - 备份：`sim/backups/bit_final_614270A8_20261031.bit`
  - slices **87.74%**；`sd +0.320/+0.014`、`video +11.732/+0.003`、`ext_mem +0.933/+0.021` → **setup + hold 全绿、0 违例**
- **改动**：`mask_hide` 去掉 `menu_panel_vis` —— 设置面板打开时**不再隐藏左上角中文角标**；
  面板位置/行坐标保持原样（用户要求"面板不需要动"）。放大约束不变（放大时仍隐藏角标）。
- **换卡**：用户换了一张旧 SD 卡（`E:` FAT32 3.65GB），已清理旧内容并重写：
  - 删除旧 `PIC1~4.BMP`（其中 PIC1 仅 0.56MB）与 8 个废弃 `TXT*.BIN`；
  - 写入 `PIC1~4.BMP`（1280×960 / 1280×960 / 1280×720 / 1024×1024，24bit 无压缩）+ `TRACK01~03.RAW`；
  - 校验：BMP 头 `24bit comp=0` ✓；RAW 为裸 PCM（首 16 字节全 0）✓。
- **上板结论**：用户确认"全部正常"——4 页显示、角标、面板叠加、切页、放大、频谱、切歌均正常。

"""
t = entry + t
io.open(p, "w", encoding="utf-8", newline="\n").write(t)
print("项目进度.md 已追加 13:35 条目")

# ---------------- 项目方案.md ----------------
p2 = BASE + r"\doc\项目方案.md"
s = io.open(p2, "r", encoding="utf-8").read()

reps = [
    ("- **固件**：**`76E808FEFCA6A4F1343518BED7CB25B5`**（4 bank + 每页几何 + 中文角标 + 频谱贴底 + 2× 商品放大，**零时序违例**）\n  - 备份：`sim/backups/bit_zero_viol_76E808FE_20261031.bit`（上一版 2× 基线：`bit_2x_DD3ACA48_20261031.bit`）",
     "- **固件**：**`614270A8D5D7905C2B40E89A5E488F72`**（4 bank + 每页几何 + 中文角标（面板打开也显示）+ 频谱贴底 + 2× 商品放大，**零时序违例**）\n  - 备份：`sim/backups/bit_final_614270A8_20261031.bit`；历史：`bit_zero_viol_76E808FE`、`bit_2x_DD3ACA48`"),
    ("| 面积 | slices ≈ **88.09%**（定稿 `76E808FE`，删除上采样 FSM 后）；LUT ≈ 9.5k、REG ≈ 8.9k；BRAM9K 15/64、BRAM32K 0 |",
     "| 面积 | slices ≈ **87.74%**（定稿 `614270A8`）；LUT ≈ 9.4k、REG ≈ 8.8k；BRAM9K 15/64、BRAM32K 0 |"),
    ("| 时序 | **setup + hold 全绿、0 违例**：`sd +0.495 / +0.014`、`video +9.973 / +0.011`、`ext_mem +0.804 / +0.112`（2026-10-31 删上采样后达成）|",
     "| 时序 | **setup + hold 全绿、0 违例**：`sd +0.320 / +0.014`、`video +11.732 / +0.003`、`ext_mem +0.933 / +0.021`（定稿 `614270A8`）|"),
]

n = 0
for a, b in reps:
    if a in s:
        s = s.replace(a, b)
        n += 1

# 功能表补一行：面板与角标的关系
anchor = "| 加分④ | 实时参数调节 + OSD：设置面板 + 右上角（歌名 + 曲目倒计时）+ 左上角（`PAGE n/4`），**常驻显示** | ✅ |"
newrow = "| 加分④ | 实时参数调节 + OSD：设置面板 + 右上角（歌名 + 曲目倒计时）+ **左上角中文角标**（设置面板打开时仍显示） | ✅ 2026-10-31 |"
if anchor in s:
    s = s.replace(anchor, newrow)
    n += 1

io.open(p2, "w", encoding="utf-8", newline="\n").write(s)
print("项目方案.md 替换 %d 处" % n)

# ---------------- TF卡 README 追加换卡说明 ----------------
p3 = BASE + r"\doc\TF卡\README.md"
r = io.open(p3, "r", encoding="utf-8").read()
note = """
> **换卡记录（2026-10-31 13:30）**：交付改用一张旧卡（`E:`，FAT32，3.65GB，剩 3.7GB）。
> 已清理其原有旧图与 8 个废弃 `TXT*.BIN`，并写入上表 4 张图 + 3 首 RAW；校验通过（BMP 24bit 无压缩、RAW 为裸 PCM）。
"""
if "换卡记录" not in r:
    marker = "> 固件只识别 `PIC1~PIC4`"
    if marker in r:
        r = r.replace(marker, note + "\n" + marker)
    else:
        r = r + note
    io.open(p3, "w", encoding="utf-8", newline="\n").write(r)
    print("TF卡/README.md 已追加换卡记录")
