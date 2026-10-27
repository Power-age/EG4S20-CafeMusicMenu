import io
from pathlib import Path

HDL = Path(r"D:\AAA_University\Anlu\Project\src\user_source\hdl_source")

# ---------- 1) sd_card_bmp：按 bank 记录源尺寸并输出 ----------
p = HDL / "SD" / "sd_card_bmp.v"
s = io.open(p, encoding="utf-8").read()

s = s.replace("""    output [6:0]                cur_track_dur_mm,   // 当前曲目总长（分）
    output [5:0]                cur_track_dur_ss    // 当前曲目总长（秒）""",
"""    output [6:0]                cur_track_dur_mm,   // 当前曲目总长（分）
    output [5:0]                cur_track_dur_ss,   // 当前曲目总长（秒）
    output [63:0]               bank_src_w,         // 四个 bank 各自的源宽（4 x 16bit）
    output [63:0]               bank_src_h          // 四个 bank 各自的源高""")

anchor = """                bank_valid[load_idx]  <= 1'b1;"""
assert anchor in s
s = s.replace(anchor, """                bank_valid[load_idx]  <= 1'b1;
                bank_src_w_r[{load_idx, 4'b0000} +: 16] <= pending_active_width;
                bank_src_h_r[{load_idx, 4'b0000} +: 16] <= pending_active_height;""")

s = s.replace("assign cur_track_dur_mm = dur_mm_r;",
"""// 2026/10/24：按 bank 记录源尺寸，供左上角信息条按"当前显示 bank"选择
reg  [63:0] bank_src_w_r;
reg  [63:0] bank_src_h_r;
assign bank_src_w = bank_src_w_r;
assign bank_src_h = bank_src_h_r;

assign cur_track_dur_mm = dur_mm_r;""")

io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("sd_card_bmp patched")

# ---------- 2) 顶层：同步 bank 尺寸并按当前 bank 选择 ----------
t = HDL / "top_tf_hdmi_audio.v"
s = io.open(t, encoding="utf-8").read()

s = s.replace("wire [15:0] display_active_width_sd;",
"""wire [15:0] display_active_width_sd;
wire [63:0] bank_src_w_sd;
wire [63:0] bank_src_h_sd;
reg  [63:0] bsw_meta, bsw_sync;
reg  [63:0] bsh_meta, bsh_sync;""")

s = s.replace("    .cur_track_dur_ss  (cur_track_dur_ss_sd)",
              "    .cur_track_dur_ss  (cur_track_dur_ss_sd),\n    .bank_src_w        (bank_src_w_sd),\n    .bank_src_h        (bank_src_h_sd)")

s = s.replace("        tks_meta <= cur_track_dur_ss_sd; tks_sync <= tks_meta;",
"""        tks_meta <= cur_track_dur_ss_sd; tks_sync <= tks_meta;
        bsw_meta <= bank_src_w_sd; bsw_sync <= bsw_meta;
        bsh_meta <= bank_src_h_sd; bsh_sync <= bsh_meta;""")

s = s.replace("""src_info_render u_src_info_render (
    .clk       (video_clk),
    .rst       (rst_all),
    .img_idx   (e2_disp_buf_sync),
    .src_w     (e2_active_width_sync),
    .src_h     (e2_active_height_sync),""",
"""wire [15:0] cur_src_w = bsw_sync[{e2_disp_buf_sync, 4'b0000} +: 16];
wire [15:0] cur_src_h = bsh_sync[{e2_disp_buf_sync, 4'b0000} +: 16];

src_info_render u_src_info_render (
    .clk       (video_clk),
    .rst       (rst_all),
    .img_idx   (e2_disp_buf_sync),
    .src_w     (cur_src_w),
    .src_h     (cur_src_h),""")

io.open(t, "w", encoding="utf-8", newline="\n").write(s)
print("top patched")

# ---------- 3) 覆盖层：左底条高度与右上角一致（22px），文字窗口仍 14px ----------
o = HDL / "osd_buffer_overlay.v"
s = io.open(o, encoding="utf-8").read()

old = """    localparam [10:0] SIT_X0 = 11'd8;
    localparam [10:0] SIT_X1 = 11'd200;
    localparam [9:0]  SIT_Y0 = 10'd12;
    wire bg_win_l = I_de
                 && (x_cnt >= SIT_X0) && (x_cnt < SIT_X1)
                 && (y_cnt >= SIT_Y0) && (y_cnt < (SIT_Y0 + 10'd14));
    wire edge_row_l = (y_cnt < (SIT_Y0 + 10'd2))
                   || (y_cnt >= (SIT_Y0 + 10'd12));
    wire bg_any   = bg_win | bg_win_l;
    wire edge_any = bg_win_l ? edge_row_l : edge_row;
    // 左上文字窗口（与底条同区）
    wire sit_win  = bg_win_l;
    wire [10:0] sit_rel_x = x_cnt - SIT_X0;
    wire [9:0]  sit_rel_y = y_cnt - SIT_Y0;"""
new = """    // 左底条与右上角**同高同 y**（OSD_Y0=8、OSD_H=22），文字窗口内缩 4px
    localparam [10:0] SIT_X0 = 11'd8;
    localparam [10:0] SIT_X1 = 11'd200;
    wire bg_win_l = I_de
                 && (x_cnt >= SIT_X0) && (x_cnt < SIT_X1)
                 && (y_cnt >= OSD_Y0) && (y_cnt < (OSD_Y0 + OSD_H));
    wire edge_row_l = (y_cnt < (OSD_Y0 + 10'd2))
                   || (y_cnt >= (OSD_Y0 + OSD_H - 10'd2));
    wire bg_any   = bg_win | bg_win_l;
    wire edge_any = bg_win_l ? edge_row_l : edge_row;
    // 文字窗口：x 8~200、y 12~26（在底条内部居中，7 行 x 2px）
    wire sit_win  = I_de
                 && (x_cnt >= SIT_X0) && (x_cnt < SIT_X1)
                 && (y_cnt >= (OSD_Y0 + 10'd4)) && (y_cnt < (OSD_Y0 + 10'd18));
    wire [10:0] sit_rel_x = x_cnt - SIT_X0;
    wire [9:0]  sit_rel_y = y_cnt - (OSD_Y0 + 10'd4);"""
assert old in s, "overlay left banner anchor missing"
s = s.replace(old, new)
io.open(o, "w", encoding="utf-8", newline="\n").write(s)
print("overlay patched")
