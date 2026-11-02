import io, re

PATH = r"D:\AAA_University\Anlu\Project\src\user_source\hdl_source\SD\bmp_read.v"
s = io.open(PATH, "r", encoding="utf-8").read()

# 1) 状态转移里的 UP 分支：从 ST_UP_PREP 到 default 之前
cnt = 0
while True:
    i = s.find("            ST_UP_PREP: begin")
    if i < 0:
        break
    j = s.find("            default:", i)
    if j < 0:
        break
    s = s[:i] + s[j:]
    cnt += 1
print("删除 UP 分支块:", cnt)

# 2) 转移语句：不再进入上采样
s = s.replace("state     <= upscale_needed ? ST_UP_PREP : ST_LOAD_DATA;",
              "state     <= ST_LOAD_DATA;   // 2026-10-31 上采样已移除")
# 兼容不同缩进
s = re.sub(r"state\s*<=\s*upscale_needed\s*\?\s*ST_UP_PREP\s*:\s*ST_LOAD_DATA;",
           "state     <= ST_LOAD_DATA;   // 2026-10-31 上采样已移除", s)

io.open(PATH, "w", encoding="utf-8", newline="\n").write(s)
print("剩余 ST_UP_ 引用:", s.count("ST_UP_"))
