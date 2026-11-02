import io

PATH = r"D:\AAA_University\Anlu\Project\src\user_source\hdl_source\top_tf_hdmi_audio.v"
s = io.open(PATH, "r", encoding="utf-8").read()

# ---------- Z4：按键统一 + 切页退出 ----------
old_key = """        vs_0_d <= vs_0;
        if (e2_disp_buf_sync == 2'd0)
            zoom_sel <= 2'd0;                       // 封面页强制退出放大
        else if (key3_long_v && !menu_panel_vis)
            zoom_sel <= (zoom_sel == 2'd1) ? 2'd0 : 2'd1;
        else if (zoom_key_r)
            zoom_sel <= (zoom_sel == 2'd2) ? 2'd0 : 2'd2;
        if (vs_0 != vs_0_d)
            zoom_sel_v <= zoom_sel;"""
new_key = """        vs_0_d <= vs_0;
        // 2026-10-31 Z4：两个放大键功能一致（任一键切换）；切页/封面页强制退出放大
        if (e2_disp_buf_sync == 2'd0)
            zoom_sel <= 2'd0;
        else if (e2_disp_changed)
            zoom_sel <= 2'd0;                       // 放大中切页 -> 回到正常视图
        else if ((key3_long_v || zoom_key_r) && !menu_panel_vis)
            zoom_sel <= (zoom_sel == 2'd2) ? 2'd0 : 2'd2;
        if (vs_0 != vs_0_d)
            zoom_sel_v <= zoom_sel;"""

assert old_key in s, "按键块未匹配"
s = s.replace(old_key, new_key)

# ---------- Z1：放大窗口描框（红框，编译期开关） ----------
old_out = """video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_vs          (osd_vs),
    .I_de          (osd_de),
        .I_rgb         (vout_data_mask),"""
new_out = """// ===== Z1 标定：在最终画面上描出当前页的放大窗口（320x240 红框） =====
// ZOOM_BOX_EN=1 时用于标定窗口位置；标定完成后置 0 即可关闭（几乎零成本）
localparam ZOOM_BOX_EN = 1'b1;
wire [9:0] zb_x0 = zm_col_sel;
wire [9:0] zb_y0 = zm_row_sel;
wire [9:0] zb_x1 = zm_col_sel + 10'd319;
wire [9:0] zb_y1 = zm_row_sel + 10'd239;
wire zb_h = ((video_y_cnt == zb_y0) || (video_y_cnt == zb_y1)) &&
            (video_x_cnt >= zb_x0) && (video_x_cnt <= zb_x1);
wire zb_v = ((video_x_cnt == zb_x0) || (video_x_cnt == zb_x1)) &&
            (video_y_cnt >= zb_y0) && (video_y_cnt <= zb_y1);
wire [23:0] vout_data_box = (ZOOM_BOX_EN && osd_de && (zb_h || zb_v)) ? 24'hFF0000 : vout_data_mask;

video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_vs          (osd_vs),
    .I_de          (osd_de),
        .I_rgb         (vout_data_box),"""

assert old_out in s, "输出块未匹配"
s = s.replace(old_out, new_out)

io.open(PATH, "w", encoding="utf-8", newline="\n").write(s)
print("Z1 + Z4 已写入 top")
