import io

PATH = r"D:\AAA_University\Anlu\Project\src\user_source\hdl_source\video_effect_overlay.v"
lines = io.open(PATH, "r", encoding="utf-8").read().splitlines(True)

# 1) 找误插入的块：第 6 行(index 5)开始，到含 "adjusted_rgb;" 的行(index 33)
mis_start = 5
mis_end = None
for i in range(mis_start, len(lines)):
    if "adjusted_rgb;" in lines[i]:
        mis_end = i
        break
assert mis_end is not None
block = lines[mis_start:mis_end + 1]

# 新块内容（把首行注释拆出来）
new_block = []
for ln in block:
    new_block.append(ln)

# 2) 删除误插块
rest = lines[:mis_start] + lines[mis_end + 1:]

# 3) 找旧转场块（"// ---------------- 转场（揭幕扫边 + 遮罩）" 到 "// ---------------- 淡入淡出" 前）
old_start = None
old_end = None
for i, ln in enumerate(rest):
    if old_start is None and "转场（揭幕扫边" in ln:
        old_start = i
    elif old_start is not None and "淡入淡出" in ln and ln.strip().startswith("//"):
        old_end = i
        break
assert old_start is not None and old_end is not None, (old_start, old_end)

out = rest[:old_start] + new_block + ["\n"] + rest[old_end:]
io.open(PATH, "w", encoding="utf-8", newline="\n").write("".join(out))
print("修复完成：删除误插块 %d 行，替换旧块 %d..%d" % (mis_end - mis_start + 1, old_start + 1, old_end))
