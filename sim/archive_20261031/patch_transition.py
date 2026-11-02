import io
import re

PATH = r"D:\AAA_University\Anlu\Project\src\user_source\hdl_source\video_effect_overlay.v"
src = io.open(PATH, "r", encoding="utf-8").read().splitlines()

# 定位旧的转场合成块（从 "转场" 注释到 "淡入淡出" 注释之前）
start = None
end = None
for i, line in enumerate(src):
    if start is None and "转场" in line and "reveal" in "".join(src[max(0, i):i + 4]):
        start = i
    if start is not None and "淡入淡出" in line and i > start:
        end = i
        break
assert start is not None and end is not None, (start, end)

new_block = """    // ---------------- 转场：横向 / 上下 / 中间向两侧（均基于遮罩，无需双帧）----------------
    wire [10:0] rx  = {1'b0, reveal_s2};
    wire [10:0] yth = rx - (rx >> 2);              // 纵向阈值：reveal=640 时到 480（整屏露出）
    wire [10:0] dth = (rx >> 1);                   // 中间向两侧：中心距离阈值
    wire [10:0] dcol = (x_cnt > 11'd320) ? (x_cnt - 11'd320) : (11'd320 - x_cnt);
    wire [10:0] ycur = {1'b0, y_s2};

    wire [10:0] thr = (mode_s2 == 2'd2) ? yth :
                      (mode_s2 == 2'd3) ? dth : rx;
    wire [10:0] cur = (mode_s2 == 2'd2) ? ycur :
                      (mode_s2 == 2'd3) ? dcol : x_cnt;

    wire [10:0] e1 = thr + 11'd6;
    wire [10:0] e2 = thr + 11'd12;
    wire [10:0] e3 = thr + 11'd18;
    wire [10:0] e4 = thr + {5'd0, TRANSITION_SOFT_WIDTH};

    wire edge0_area = tactive_s2 && I_de && (cur >= thr) && (cur < e1);
    wire edge1_area = tactive_s2 && I_de && (cur >= e1)  && (cur < e2);
    wire edge2_area = tactive_s2 && I_de && (cur >= e2)  && (cur < e3);
    wire edge3_area = tactive_s2 && I_de && (cur >= e3)  && (cur < e4);
    wire mask_area  = tactive_s2 && I_de && (cur >= e4);

    wire [23:0] transition_rgb = mask_area  ? TRANSITION_MASK_COLOR :
                                 edge3_area ? TRANSITION_EDGE3_COLOR :
                                 edge2_area ? TRANSITION_EDGE2_COLOR :
                                 edge1_area ? TRANSITION_EDGE1_COLOR :
                                 edge0_area ? TRANSITION_EDGE0_COLOR :
                                              adjusted_rgb;

""".splitlines()

out = src[:start] + new_block + src[end:]
io.open(PATH, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")
print("替换完成：旧块行 %d..%d" % (start + 1, end))
