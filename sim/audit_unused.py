"""审计 hdl_source 下的模块：谁是顶层可达、谁没人实例化（清理候选）。"""
import re
from pathlib import Path

ROOT = Path(r"D:\AAA_University\Anlu\Project\src\user_source\hdl_source")
PRJ = [
    Path(r"D:\AAA_University\Anlu\Project\src\td_project\HDMI1.4b_Transmitter_v1.0_Runs\syn_1\HDMI1.4b_Transmitter_v1.0.prj"),
    Path(r"D:\AAA_University\Anlu\Project\src\td_project\HDMI1.4b_Transmitter_v1.0_Runs\phy_1\HDMI1.4b_Transmitter_v1.0.prj"),
]

files = {p: p.read_text(encoding="utf-8", errors="ignore") for p in ROOT.rglob("*.v")}
mod_of = {}
for p, txt in files.items():
    m = re.search(r"^\s*module\s+(\w+)", txt, re.M)
    if m:
        mod_of[p] = m.group(1)

# 统计每个模块被实例化的次数（排除自身定义）
inst = {}
for name in mod_of.values():
    n = 0
    for p, txt in files.items():
        if mod_of.get(p) == name:
            txt2 = txt
        else:
            txt2 = txt
        # 实例化形如:  name u_xxx (  或  name #( ... ) u_xxx
        for mm in re.finditer(r"\b%s\s*(#\s*\([^;]*?\)\s*)?(\w+)\s*\(" % re.escape(name), txt2, re.S):
            if mod_of.get(p) == name and mm.start() < txt2.find("endmodule"):
                # 定义处不算；仅当出现在自身文件里也跳过
                if mod_of.get(p) == name:
                    continue
            n += 1
    inst[name] = n

prj_txt = ""
for p in PRJ:
    if p.exists():
        prj_txt += p.read_text(encoding="utf-8", errors="ignore")

print("%-34s %-26s %6s %6s" % ("文件", "模块", "实例数", "在prj"))
print("-" * 78)
dead = []
for p in sorted(mod_of, key=lambda x: str(x)):
    name = mod_of[p]
    n = inst.get(name, 0)
    inprj = "Y" if (name + ".v") in prj_txt else "-"
    if n == 0:
        dead.append((p.name, name, inprj))
for f, n, ip in sorted(dead):
    print("%-34s %-26s %6d %6s" % (f, n, 0, ip))
print("\n无人实例化的模块数:", len(dead), " / 总模块数:", len(mod_of))
