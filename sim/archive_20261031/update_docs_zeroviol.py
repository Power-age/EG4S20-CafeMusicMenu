import io

BASE = r"D:\AAA_University\Anlu\Project"

# ---------- 项目进度.md ----------
p = BASE + r"\doc\项目进度.md"
t = io.open(p, "r", encoding="utf-8").read()
entry = """### 2026-10-31 11:20 **零时序违例达成（保留放大功能）**

- **固件**：**`76E808FEFCA6A4F1343518BED7CB25B5`**（已烧录）
  - 备份：`sim/backups/bit_zero_viol_76E808FE_20261031.bit`
- **做法**：物理删除 `bmp_read.v` 里**上采样 FSM 的 5 个状态分支**（`ST_UP_PREP/READ/SCALE/EMIT/FETCH/REPEAT`，共 128 行），
  并把 `ST_LOAD_WAIT` 的转移改为直接进 `ST_LOAD_DATA`。上采样本就在 2026-10-31 被功能关闭（素材规格 ≥640×480）。
- **结果**：
  | 指标 | 删除前 | 删除后 |
  |---|---|---|
  | slices | 91.77% | **88.09%**（省 3.68%）|
  | sd setup / hold | +0.558 / +0.084 | +0.495 / **+0.014** |
  | video setup / hold | +10.762 / **−0.005** | +9.973 / **+0.011** |
  | ext_mem setup / hold | +0.168 / **−0.004** | +0.804 / **+0.112** |
  | 门禁 | ✗ 拦住 | ✅ 通过 |
- **关键结论**：hold 残差的**根因是密度**，不是路径本身——占地 3.68% 的上采样死逻辑把布线推到 `fix_hold` 插不进缓冲的程度。
  之前"关放大"实验（89.59%）也能清零，与此互为印证。
- **对照实验**：`sim\tb_bmp_read.v` 在"改动前/后"两个版本的输出完全一致（都是 `map_rows=1`），证明该 tb 已过期、不能作为回归依据；装载通路的真实验证需上板。
- **构建流程**：`sim/DefaultFlow_hold.tcl` 的 `fix_hold` 由 1 轮改为 3 轮（实测第 2、3 轮为空操作，留作保险）。

"""
t = entry + t
io.open(p, "w", encoding="utf-8", newline="\n").write(t)
print("项目进度.md 已追加零违例条目")

# ---------- 项目方案.md ----------
p2 = BASE + r"\doc\项目方案.md"
s = io.open(p2, "r", encoding="utf-8").read()

reps = [
    ("- **固件**：`DD3ACA481D576245C33F920CEBA2114B`（4 bank + 每页几何 + 中文角标 + 频谱贴底 + 2× 商品放大）\n  - 备份：`sim/backups/bit_2x_DD3ACA48_20261031.bit`",
     "- **固件**：**`76E808FEFCA6A4F1343518BED7CB25B5`**（4 bank + 每页几何 + 中文角标 + 频谱贴底 + 2× 商品放大，**零时序违例**）\n  - 备份：`sim/backups/bit_zero_viol_76E808FE_20261031.bit`（上一版 2× 基线：`bit_2x_DD3ACA48_20261031.bit`）"),
    ("| 面积 | slices ≈ **90.98%**（定稿 `DD3ACA48`）；LUT ≈ 10.0k、REG ≈ 9.1k；BRAM9K 15/64、BRAM32K 0 |",
     "| 面积 | slices ≈ **88.09%**（定稿 `76E808FE`，删除上采样 FSM 后）；LUT ≈ 9.5k、REG ≈ 8.9k；BRAM9K 15/64、BRAM32K 0 |"),
    ("| 时序 | **setup 全绿**：`sd +0.24` / `video +11.4` / `ext_mem +0.71`；**hold 残差 −4~20ps**（BRAM 地址短路径，已接受，见 §7.4）|",
     "| 时序 | **setup + hold 全绿、0 违例**：`sd +0.495 / +0.014`、`video +9.973 / +0.011`、`ext_mem +0.804 / +0.112`（2026-10-31 删上采样后达成）|"),
    ("| 5 | **hold 残差 −4~20ps** | 报告非零违例；功能实测正常 | **接受**（用户 2026-10-31 决定），详见 §7.4 |",
     "| 5 | ~~hold 残差 −4~20ps~~ | — | ✅ **已解决**：根因是密度，删除上采样 FSM 后 slices 91.77%→88.09%，hold 全部转正（§7.4）|"),
]

n = 0
for a, b in reps:
    if a in s:
        s = s.replace(a, b)
        n += 1

# §7.4 标题与结论更新
s = s.replace("### 7.4 hold 残差的定位与可选路线（2026-10-31）",
              "### 7.4 hold 残差：定位过程与最终解决（2026-10-31）")
s = s.replace("**三条可选路线**（本次均未采纳，留档）：",
              "**最终采用**：路线 ② 的变体——**物理删除上采样 FSM**（该功能已按素材规格关闭）。删除后 slices 91.77%→88.09%，hold 全部转正、0 违例。\n\n**其余两条路线（留档）：**")

io.open(p2, "w", encoding="utf-8", newline="\n").write(s)
print("项目方案.md 替换 %d 处" % n)
