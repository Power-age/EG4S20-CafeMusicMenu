"""把工程当前的源码/文档同步进 GitHub 仓库工作副本（保留 .git）。

策略：对每个受管子目录，先删除仓库内的旧副本，再从工程按白名单拷贝，
然后由 git add -A 自动把删除与新增一并暂存。
"""
import fnmatch
import io
import os
import shutil

SRC = r"D:\AAA_University\Anlu\Project"
DST = r"D:\AAA_University\Anlu\EG4S20-CafeMusicMenu"

SKIP = ["*.bak", "*.bak2", "*.bak20261024", "*.v5bak", "*.ui_ctlbak", "*.v213bbak",
        "*.dath", "song_48k.mif", "*.db", "*.bit", "*.dmp", "*.orig", "*.rej"]


def keep(name):
    low = name.lower()
    return not any(fnmatch.fnmatch(low, p.lower()) for p in SKIP)


def copy_into(src_rel, dst_rel, exts=None):
    s = os.path.join(SRC, src_rel)
    d = os.path.join(DST, dst_rel)
    if not os.path.isdir(s):
        return 0
    if os.path.isdir(d):
        shutil.rmtree(d)
    n = 0
    for root, dirs, files in os.walk(s):
        dirs[:] = [x for x in dirs if x not in ("work", "__pycache__", ".git")]
        for f in files:
            if not keep(f):
                continue
            if exts and not any(f.lower().endswith(e) for e in exts):
                continue
            full = os.path.join(root, f)
            rel = os.path.relpath(full, s)
            out = os.path.join(d, rel)
            os.makedirs(os.path.dirname(out), exist_ok=True)
            shutil.copy2(full, out)
            n += 1
    return n


total = 0
# 1) HDL 源码 / 约束 / IP / mask ROM / 生成脚本
total += copy_into(r"src\user_source", r"src\user_source")
# 2) TD 工程（.al）
total += copy_into(r"src\td_project", r"src\td_project", exts=[".al"])
# 3) 两个 run 的工程/配置
for run in ("syn_1", "phy_1"):
    s = os.path.join(SRC, "src", "td_project", "HDMI1.4b_Transmitter_v1.0_Runs", run)
    d = os.path.join(DST, "src", "td_project", "HDMI1.4b_Transmitter_v1.0_Runs", run)
    if os.path.isdir(d):
        shutil.rmtree(d)
    os.makedirs(d, exist_ok=True)
    for f in ("HDMI1.4b_Transmitter_v1.0.prj", "HDMI1.4b_Transmitter_v1.0.tcl", "settings.cfg"):
        p = os.path.join(s, f)
        if os.path.isfile(p):
            shutil.copy2(p, os.path.join(d, f))
            total += 1
# 4) 仿真/脚本
total += copy_into("sim", "sim", exts=[".py", ".ps1", ".v", ".tcl", ".md"])
# 5) 文档（根 + docx + 归档）
doc_dst = os.path.join(DST, "doc")
if os.path.isdir(doc_dst):
    shutil.rmtree(doc_dst)
os.makedirs(doc_dst, exist_ok=True)
for f in os.listdir(os.path.join(SRC, "doc")):
    p = os.path.join(SRC, "doc", f)
    if os.path.isfile(p) and (f.lower().endswith(".md") or f.lower().endswith(".docx")):
        shutil.copy2(p, os.path.join(doc_dst, f))
        total += 1
total += copy_into(r"doc\archive", r"doc\archive", exts=[".md"])

size = 0
count = 0
for root, _, files in os.walk(DST):
    if ".git" in root.split(os.sep):
        continue
    for f in files:
        count += 1
        size += os.path.getsize(os.path.join(root, f))
print("同步文件数:", total, "| 仓库工作副本:", count, "个文件, %.2f MB" % (size / 1048576.0))
