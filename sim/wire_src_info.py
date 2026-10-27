import io
from pathlib import Path

# ---------- 1) 覆盖层：加左上窗口 + 与之统一的下底条 ----------
o = Path(r"D:\AAA_University\Anlu\Project\src\user_source\hdl_source\osd_buffer_overlay.v")
s = io.open(o, encoding="utf-8").read()

old_geo = """    wire bg_win = I_de
               && (x_cnt >= OSD_X0) && (x_cnt < (OSD_X0 + OSD_W))
               && (y_cnt >= OSD_Y0) && (y_cnt < (OSD_Y0 + OSD_H));
    wire edge_row = (y_cnt < (OSD_Y0 + 10'd2))
                  || (y_cnt >= (OSD_Y0 + OSD_H - 10'd2));"""
new_geo = """    wire bg_win = I_de
               && (x_cnt >= OSD_X0) && (x_cnt < (OSD_X0 + OSD_W))
               && (y_cnt >= OSD_Y0) && (y_cnt < (OSD_Y0 + OSD_H));
    wire edge_row = (y_cnt < (OSD_Y0 + 10'd2))
                  || (y_cnt >= (OSD_Y0 + OSD_H - 10'd2));

    // 2026/10/24 左上角信息条：与右上角同款底条（同色同边），几何不同
    localparam [10:0] SIT_X0 = 11'd8;
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
assert old_geo in s, "geometry anchor missing"
s = s.replace(old_geo, new_geo)

old_reg = """            bg_q         <= bg_win;
            edge_q       <= bg_win & edge_row;"""
new_reg = """            bg_q         <= bg_any;
            edge_q       <= bg_any & edge_any;
            sit_q        <= sit_win;"""
assert old_reg in s, "register anchor missing"
s = s.replace(old_reg, new_reg)

old_rst = "            bg_q         <= 1'b0;\n            edge_q       <= 1'b0;"
new_rst = "            bg_q         <= 1'b0;\n            edge_q       <= 1'b0;\n            sit_q        <= 1'b0;"
assert old_rst in s, "reset anchor missing"
s = s.replace(old_rst, new_rst)

s = s.replace("    reg        edge_q;", "    reg        edge_q;\n    reg        sit_q;")

# 读地址：并入左上窗口
old_rd = """    assign rd_en = text_win || ptxt_win || stxt_win;
    assign rd_x  = ptxt_win ? ptxt_rel_x[8:1] :"""
new_rd = """    assign rd_en = text_win || sit_win || ptxt_win || stxt_win;
    assign rd_x  = sit_win  ? (8'd160 + sit_rel_x[8:1]) :
                   ptxt_win ? ptxt_rel_x[8:1] :"""
assert old_rd in s, "rd anchor missing"
s = s.replace(old_rd, new_rd)

old_rdy = """    assign rd_y  = ptxt_win ? (7'd8 + {1'b0, ptxt_rel_y[6:1]}) :"""
new_rdy = """    assign rd_y  = sit_win  ? (7'd72 + {1'b0, sit_rel_y[4:1]}) :
                   ptxt_win ? (7'd8 + {1'b0, ptxt_rel_y[6:1]}) :"""
assert old_rdy in s, "rd_y anchor missing"
s = s.replace(old_rdy, new_rdy)

# 输出：左上窗口内画文字（底条由 bg_q 覆盖，故这里只管文字）
old_out = "    assign O_rgb = bg_q ? blend_rgb : (stxt_q || stxt_bg_q) ? sub_rgb : pnl_out;"
new_out = """    // 左上角信息条文字：底条走 bg 支路，文字用暖白色
    wire sit_txt = sit_q && (rd_data == 2'b10);
    assign O_rgb = bg_q ? (sit_txt ? TEXT_COLOR : blend_rgb) :
                   (stxt_q || stxt_bg_q) ? sub_rgb : pnl_out;"""
assert old_out in s, "output anchor missing"
s = s.replace(old_out, new_out)

io.open(o, "w", encoding="utf-8", newline="\n").write(s)
print("overlay patched")

# ---------- 2) 顶层：声明 + 实例 + 仲裁 ----------
t = Path(r"D:\AAA_University\Anlu\Project\src\user_source\hdl_source\top_tf_hdmi_audio.v")
s = io.open(t, encoding="utf-8").read()

s = s.replace("wire        use_w5;", """wire        use_w5;
// 左上角信息条（源分辨率）
wire        si_req_valid;
wire [6:0]  si_req_ascii;
wire [7:0]  si_req_x;
wire [6:0]  si_req_y;
wire [1:0]  si_req_type;
wire        si_req_ready;
wire        si_busy;""", 1)

s = s.replace("assign osd_req_valid = menu_busy ? menu_req_valid : (sub_busy ? sub_req_valid : sb_req_valid);",
              "assign osd_req_valid = menu_busy ? menu_req_valid : (sub_busy ? sub_req_valid : (sb_req_valid ? sb_req_valid : si_req_valid));")
s = s.replace("assign osd_req_ascii = menu_busy ? menu_req_ascii : (sub_busy ? sub_req_ascii : sb_req_ascii);",
              "assign osd_req_ascii = menu_busy ? menu_req_ascii : (sub_busy ? sub_req_ascii : (sb_req_valid ? sb_req_ascii : si_req_ascii));")
s = s.replace("assign osd_req_x     = menu_busy ? menu_req_x     : (sub_busy ? sub_req_x     : sb_req_x);",
              "assign osd_req_x     = menu_busy ? menu_req_x     : (sub_busy ? sub_req_x     : (sb_req_valid ? sb_req_x : si_req_x));")
s = s.replace("assign osd_req_y     = menu_busy ? menu_req_y     : (sub_busy ? sub_req_y     : sb_req_y);",
              "assign osd_req_y     = menu_busy ? menu_req_y     : (sub_busy ? sub_req_y     : (sb_req_valid ? sb_req_y : si_req_y));")
s = s.replace("assign osd_req_type  = menu_busy ? menu_req_type  : (sub_busy ? sub_req_type  : sb_req_type);",
              "assign osd_req_type  = menu_busy ? menu_req_type  : (sub_busy ? sub_req_type  : (sb_req_valid ? sb_req_type : si_req_type));")
s = s.replace("assign use_w5        = menu_busy | sub_busy | sb_req_valid;",
              "assign use_w5        = menu_busy | sub_busy | sb_req_valid | si_req_valid;")
s = s.replace("assign sb_req_ready   = osd_req_ready && !menu_busy && !sub_busy;",
              "assign sb_req_ready   = osd_req_ready && !menu_busy && !sub_busy;\nassign si_req_ready   = osd_req_ready && !menu_busy && !sub_busy && !sb_req_valid;")

s = s.replace("// ---- 曲目倒计时（视频域，供右上角状态栏显示剩余 MM:SS）----",
"""// ---- 左上角信息条：源分辨率 ----
src_info_render u_src_info_render (
    .clk       (video_clk),
    .rst       (rst_all),
    .img_idx   (e2_disp_buf_sync),
    .src_w     (e2_active_width_sync),
    .src_h     (e2_active_height_sync),
    .req_valid (si_req_valid),
    .req_ascii (si_req_ascii),
    .req_x     (si_req_x),
    .req_y     (si_req_y),
    .req_type  (si_req_type),
    .req_ready (si_req_ready),
    .busy      (si_busy)
);

// ---- 曲目倒计时（视频域，供右上角状态栏显示剩余 MM:SS）----""", 1)

io.open(t, "w", encoding="utf-8", newline="\n").write(s)
print("top patched")
