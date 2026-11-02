"""从 bmp_read.v 中整块删除上采样通路（素材统一 >= 640x480）。

策略：按"起始标记 + 结束标记"删除连续块，剩余的零散 up_ 引用交给编译错误逐个清。
"""
import io
import sys

P = r"D:\AAA_University\Anlu\Project\src\user_source\hdl_source\SD\bmp_read.v"
lines = io.open(P, encoding="utf-8", errors="surrogateescape").read().split("\n")


def find(pred, start=0):
    for i in range(start, len(lines)):
        if pred(lines[i]):
            return i
    return -1


def cut(a, b, tag):
    """删除 [a, b] 闭区间"""
    global lines
    if a < 0 or b < a:
        print("  [skip]", tag)
        return
    n = b - a + 1
    del lines[a:b + 1]
    print("  [cut] %-24s 行 %d..%d (%d 行)" % (tag, a + 1, b + 1, n))


# A. localparam ST_UP_*
a = find(lambda s: "localparam [4:0] ST_UP_PREP" in s)
b = find(lambda s: "localparam [4:0] ST_UP_FETCH" in s, a)
cut(a, b, "ST_UP localparam")

# B. up_* reg 声明
a = find(lambda s: "reg [15:0] up_source_y;" in s)
b = find(lambda s: "reg [31:0] up_scale_y_acc;" in s, a)
cut(a, b, "up_* reg decls")

# C. up_* wire 声明
a = find(lambda s: "wire [31:0] up_scale_x_acc_next;" in s)
b = find(lambda s: "wire [23:0] up_row_rd_data;" in s, a)
cut(a, b, "up_* wire decls")

# D. assign up_* 组
a = find(lambda s: s.strip().startswith("assign up_scale_x_acc_next"))
b = find(lambda s: s.strip().startswith("assign up_row_rd_addr"), a)
cut(a, b, "assign up_*")

# E. 行缓冲 BRAM（ifdef..endif）
a = find(lambda s: "BMP_ROW_MEM_SIM" in s)
b = find(lambda s: s.strip() == "`endif", a)
cut(a, b, "row buffer BRAM")

# F. 状态寄存器块的 ST_UP_* 分支（到 default: ; 之前）
a = find(lambda s: s.strip() == "ST_UP_PREP: begin")
b = find(lambda s: s.strip() == "default: ;", a)
cut(a, b, "ST_UP case arms (regs)")

# G. bmp_data 里 EMIT 分支
a = find(lambda s: "else if (state == ST_UP_EMIT)" in s)
while a >= 0 and "bmp_data" not in lines[a - 1] and "ST_UP_EMIT" not in lines[a - 1]:
    a2 = find(lambda s: "else if (state == ST_UP_EMIT)" in s, a + 1)
    if a2 < 0:
        break
    a = a2
if a >= 0:
    cut(a - 1, a + 3, "bmp_data EMIT branch")

# H. 状态机块的 ST_UP_* 分支（第二个 ST_UP_PREP）
a = find(lambda s: s.strip() == "ST_UP_PREP: begin")
b = find(lambda s: s.strip() == "default: ;", a)
cut(a, b, "ST_UP case arms (FSM)")

io.open(P, "w", encoding="utf-8", errors="surrogateescape", newline="\n").write("\n".join(lines))
print("剩余行数:", len(lines))
