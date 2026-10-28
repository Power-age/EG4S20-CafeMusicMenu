"""同一网表下扫多个布局种子，按"最差域的裕量最大"选最优，并把该种子的 bit 存到按种子命名的备份目录。

评价准则：score = min(sd_card, video, ext_mem)  —— 最差的那条链路优先。
"""
import os
import re
import shutil
import subprocess
import sys

RUNS = r"D:\AAA_University\Anlu\Project\src\td_project\HDMI1.4b_Transmitter_v1.0_Runs"
PHY = os.path.join(RUNS, "phy_1")
BEST = os.path.join(RUNS, "best_result")
BAK = r"D:\AAA_University\Anlu\Project\sim\backups\seed_sweep_v2"
TD = r"D:/TD5.6.2/bin/td_commands_prompt.exe"
TCL = r"D:/TD5.6.2/doc/scripts/DefaultFlow.tcl"

SEEDS = [int(s) for s in (sys.argv[1:] or ["7", "13", "17", "11"])]

os.makedirs(BAK, exist_ok=True)

def read_cfg():
    with open(os.path.join(PHY, "settings.cfg"), encoding="ascii") as f:
        return f.read()

def write_seed(seed):
    txt = read_cfg()
    txt = re.sub(r"place seed \d+", "place seed %d" % seed, txt)
    with open(os.path.join(PHY, "settings.cfg"), "w", encoding="ascii") as f:
        f.write(txt)

def clear_db():
    for name in os.listdir(PHY):
        if name.endswith((".db", ".timing")) or name in ("route.qor", "place.qor", "final_timing.rpt"):
            p = os.path.join(PHY, name)
            try:
                os.remove(p)
            except OSError:
                pass

def parse():
    out = {}
    cands = [os.path.join(PHY, "HDMI1.4b_Transmitter_v1.0_pr.timing"),
             os.path.join(PHY, "final_timing.rpt")]
    cands = [p for p in cands if os.path.exists(p)]
    if not cands:
        return {"sd_card": None, "video": None, "ext_mem": None}
    path = max(cands, key=os.path.getmtime)
    txt = open(path, encoding="utf-8", errors="ignore").read()
    for key, pat in (("sd_card", r"sd_card\s+Max\s*:\s*SWNS\s+(-?[\d.]+)"),
                     ("video", r"video\s+Max\s*:\s*SWNS\s+(-?[\d.]+)"),
                     ("ext_mem", r"ext_mem\s+Max\s*:\s*SWNS\s+(-?[\d.]+)")):
        m = re.search(pat, txt)
        out[key] = float(m.group(1)) if m else None
    return out

results = []
for seed in SEEDS:
    print("=== seed %d ===" % seed, flush=True)
    write_seed(seed)
    clear_db()
    subprocess.run([TD, TCL], cwd=PHY, capture_output=True, text=True)
    t = parse()
    if None in t.values():
        print("  parse failed", t, flush=True)
        continue
    score = min(t["sd_card"], t["video"], t["ext_mem"])
    print("  sd=%.3f video=%.3f ext=%.3f  score=%.3f" % (t["sd_card"], t["video"], t["ext_mem"], score), flush=True)
    bit = os.path.join(PHY, "HDMI1.4b_Transmitter_v1.0.bit")
    dst = os.path.join(BAK, "seed%d.bit" % seed)
    if os.path.exists(bit):
        shutil.copy2(bit, dst)
    results.append((score, seed, t, dst))

if not results:
    print("no valid result")
    sys.exit(1)

results.sort(key=lambda r: -r[0])
best = results[0]
print("\n=== 汇总（按最差域裕量降序）===")
for score, seed, t, _ in results:
    print("  seed %2d  score %+.3f  sd %+.3f  video %+.3f  ext %+.3f" % (seed, score, t["sd_card"], t["video"], t["ext_mem"]))

shutil.copy2(best[3], os.path.join(BEST, "HDMI1.4b_Transmitter_v1.0.bit"))
shutil.copy2(best[3], os.path.join(PHY, "HDMI1.4b_Transmitter_v1.0.bit"))
write_seed(best[1])
print("\n选定 seed %d（score %+.3f），已同步 best_result/phy_1 并写回 settings.cfg" % (best[1], best[0]))
