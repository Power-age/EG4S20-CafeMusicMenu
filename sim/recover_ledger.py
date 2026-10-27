import io, shutil
from pathlib import Path

DOC = Path(r"D:\AAA_University\Anlu\Project\doc")
led = DOC / "项目进度.md"
bak2 = DOC / "archive" / "20261024" / "项目进度.md.bak2"

# 1) 恢复备份
shutil.copy2(str(bak2), str(led))
lines = io.open(led, encoding="utf-8").read().split("\n")
print("恢复后行数:", len(lines))

# 2) 补记丢失区间
block = """### 2026/10/24 14:00 ~ 10/25 00:51 补记（台账曾被误覆盖，按 archive/20261024/项目进度.md.bak2 恢复后补写）

> **事故**：2026/10/24 22:40 用脚本追加记录时，同一变量先读了 `Anlu.md` 又用来写台账，导致 `项目进度.md` 被规则件内容覆盖，E18.0~E18.8 的记录丢失。已从 `archive/20261024/项目进度.md.bak2`（1160 行，到 E17 为止）恢复，本段按会话记录补写关键节点。**教训：批量写文件前必须确认"读的变量"与"写的目标"是同一个文件**（已并入规则件 B3）。

本区间稳定点与固件：

| 稳定点 | MD5 | 时间 | 内容 |
|---|---|---|---|
| E18.0 | `3593C221BDFEFC045826C37229E540E5` | 14:56 | 修按键方向竞态（key_pulse 打一拍）+ 默认亮度 4 + PIC4 降 1280×720 |
| E18.1 | `C7243C65D0C30291078230A0C6EA4870` | 15:33 | 修时间戳"固定为 0"（`frame_cnt` 自增分支丢失）+ 死代码清理；新增 `tb_status_clock` |
| E18.2 | `9EABCEFCDBD043E5D8C040336EEAEB15` | 16:53 | 右上角改为**曲目倒计时** `-MM:SS`（SD 域算 MM:SS、视频域数帧）；新增 `tb_track_countdown` |
| E18.3 | `1CB29BCF6E598FDE8309E93BE1239715` | 19:04 | 字幕改"滚入后固定"；删临时死机锁存 |
| E18.4 | `8445BA1705A27DC363C8859A6A9A32D1` | 19:3x | 文案压到 ≤32 字符、静态整行显示 |
| E18.5 | `20C5681EC5F5C5496C16EED856BA9D70` | 19:4x | 字幕改"整条从左侧滑入 + 15 字符/秒"，滑到位停住 |
| E18.6 | `BD3B7A877A809CDC688D22068438A574` | 19:45 | 菜单重绘加 `redraw_pending`（防重绘打断，未治本）|
| E18.7 | `A2FF13D71D89DA4E184C8AE6AA193A2A` | 19:56 | **菜单最后一行半截真因修复**：字幕存储行 60~66 与面板行 64~70 冲突 → 字幕改存行 0~6 |
| E18.8 | `07609DE6DC33EE163CEC8E7D8907E6B6` | 23:12 | 左上角信息条初版（面积 96.59%）|
| E18.9 | `2CDFBFABB8AC5B3F4D117824DF3A02FC` | 10/25 00:51 | 左上角信息条**改为固定常量表**、修上电不显示；验收通过 |

本区间其它重要事项：
- **文档体系重构**：`doc/` 归档旧方案到 `archive/20261024/`；方案件由 `Anlu_当前方案.md` 更名为 `项目方案.md`（早期同名文件已归档）；`Anlu_决策纪要.md` 并入方案件**附录 A** 后删除；规则件 `Anlu.md` 做两次修订（新增 B1~B9 共 9 条、纠正 7 处、加严 2 处）。
- **交付件重写**：`工程交互使用说明文档.md` §1/§5.3/§6/§10 按当前实现重写，§10 改为**按赛题采分顺序**的演示流程。
- **赛题核对结论**：五条基础要求中唯一缺口是**基础③"基础音频输出（测试音）"**；五条加分项均已实现。
- **烧录方式打通**：`bw_commands_prompt.exe` + `download -mode jtag`（SRAM，掉电丢失，7 秒）；固化 `PROGRAM_FLASH` 由用户在 GUI 完成。
- **面积演进**：E18.1 93.88% → 加倒计时 95.15% → 左上角信息条一度 97.67% → 改固定表后 **95.11%**。

---

"""
io.open(led, "w", encoding="utf-8", newline="\n").write(block + "\n".join(lines))
out = io.open(led, encoding="utf-8").read().split("\n")
print("补记后行数:", len(out))
print("含 E18.9:", any("E18.9" in l for l in out))
print("含 稳定点 E17:", any("E17" in l for l in out))
