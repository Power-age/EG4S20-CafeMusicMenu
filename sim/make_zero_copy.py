"""建立"零违例"实验副本：只拷构建所需，跳过 DB/日志/工作区/素材。"""
import os
import shutil

SRC = r"D:\AAA_University\Anlu\Project"
DST = r"D:\AAA_University\Anlu\Project_zero"

SKIP_EXT = (".db", ".bit", ".log", ".logw", ".dmp", ".qor", ".area", ".bid",
            ".timing", ".rpt", ".ts", ".bak", ".logw")

if os.path.isdir(DST):
    shutil.rmtree(DST)


def copy_tree(rel, exts=None):
    s = os.path.join(SRC, rel)
    d = os.path.join(DST, rel)
    n = 0
    for root, dirs, files in os.walk(s):
        dirs[:] = [x for x in dirs if x not in ("work", "__pycache__", ".git", "shots", "backups")]
        for f in files:
            if f.lower().endswith(SKIP_EXT):
                continue
            if exts and not any(f.lower().endswith(e) for e in exts):
                continue
            full = os.path.join(root, f)
            out = os.path.join(d, os.path.relpath(full, s))
            os.makedirs(os.path.dirname(out), exist_ok=True)
            shutil.copy2(full, out)
            n += 1
    return n


n = 0
n += copy_tree(r"src\user_source")
n += copy_tree(r"src\td_project", exts=[".al", ".prj", ".tcl", ".cfg", ".adc", ".sdc"])
n += copy_tree(r"sim", exts=[".ps1", ".py", ".v", ".tcl", ".md"])
os.makedirs(os.path.join(DST, "doc"), exist_ok=True)

# 修正副本里的路径（build/capture 脚本硬编码了原工程路径）
for name in ("loop.ps1", "burn_jtag.tcl"):
    p = os.path.join(DST, "sim", name)
    if os.path.isfile(p):
        txt = open(p, encoding="utf-8", errors="ignore").read()
        txt = txt.replace(r"D:\AAA_University\Anlu\Project", r"D:\AAA_University\Anlu\Project_zero")
        txt = txt.replace("D:/AAA_University/Anlu/Project", "D:/AAA_University/Anlu/Project_zero")
        open(p, "w", encoding="utf-8", newline="").write(txt)

size = 0
cnt = 0
for root, _, files in os.walk(DST):
    for f in files:
        cnt += 1
        size += os.path.getsize(os.path.join(root, f))
print("副本文件:", cnt, " %.1f MB" % (size / 1048576.0))
print("meta:", n)
