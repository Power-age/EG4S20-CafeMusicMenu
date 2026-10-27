import os, shutil, fnmatch

SRC = r"D:\AAA_University\Anlu\Project"
DST = r"D:\AAA_University\Anlu\EG4S20-CafeMusicMenu"

SKIP_PATTERNS = [
    "*.bak", "*.bak2", "*.bak20261024", "*.v5bak", "*.ui_ctlbak", "*.v213bbak",
    "*.dath", "song_48k.mif", "*.db", "*.bit", "*.dmp", "*.orig", "*.rej",
]

def keep(name):
    low = name.lower()
    for pat in SKIP_PATTERNS:
        if fnmatch.fnmatch(low, pat.lower()):
            return False
    return True

def copy_tree(src_rel, dst_rel, exts=None, fn_filter=None):
    s = os.path.join(SRC, src_rel)
    if not os.path.isdir(s):
        return 0
    n = 0
    for root, dirs, files in os.walk(s):
        dirs[:] = [d for d in dirs if d not in ("work", "__pycache__", ".git")]
        for f in files:
            if not keep(f):
                continue
            if exts and not any(f.lower().endswith(e) for e in exts):
                continue
            if fn_filter and not fn_filter(f):
                continue
            full = os.path.join(root, f)
            rel = os.path.relpath(full, SRC)
            out = os.path.join(DST, rel)
            os.makedirs(os.path.dirname(out), exist_ok=True)
            shutil.copy2(full, out)
            n += 1
    return n

if os.path.isdir(DST):
    shutil.rmtree(DST)
os.makedirs(DST)

total = 0
# 1) HDL 源码、约束、IP、mask ROM、python 生成脚本
total += copy_tree(r"src\user_source", r"src\user_source")
# 2) TD 工程文件（只 .al）
total += copy_tree(r"src\td_project", r"src\td_project", exts=[".al"])
# 3) 两份 run 的工程/配置（种子、SDC 列表都在里面）
for run in ("syn_1", "phy_1"):
    s = os.path.join(SRC, "src", "td_project", "HDMI1.4b_Transmitter_v1.0_Runs", run)
    d = os.path.join(DST, "src", "td_project", "HDMI1.4b_Transmitter_v1.0_Runs", run)
    os.makedirs(d, exist_ok=True)
    for f in ("HDMI1.4b_Transmitter_v1.0.prj", "HDMI1.4b_Transmitter_v1.0.tcl", "settings.cfg"):
        p = os.path.join(s, f)
        if os.path.isfile(p):
            shutil.copy2(p, os.path.join(d, f))
            total += 1
# 4) 仿真/脚本
total += copy_tree("sim", "sim", exts=[".py", ".ps1", ".v", ".tcl", ".md"])
# 5) 文档
for f in os.listdir(os.path.join(SRC, "doc")):
    p = os.path.join(SRC, "doc", f)
    if os.path.isfile(p) and (f.lower().endswith(".md") or f.lower().endswith(".docx")):
        os.makedirs(os.path.join(DST, "doc"), exist_ok=True)
        shutil.copy2(p, os.path.join(DST, "doc", f))
        total += 1
total += copy_tree(r"doc\archive", r"doc\archive", exts=[".md"])

print("copied files:", total)
size = 0
for root, _, files in os.walk(DST):
    for f in files:
        size += os.path.getsize(os.path.join(root, f))
print("repo size: %.2f MB" % (size / 1048576.0))
big = []
for root, _, files in os.walk(DST):
    for f in files:
        p = os.path.join(root, f)
        if os.path.getsize(p) > 1024 * 1024:
            big.append((os.path.getsize(p), os.path.relpath(p, DST)))
big.sort(reverse=True)
print("files >1MB:", big[:10])
