module osd_buffer_overlay (
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_de,
    input  wire        I_vs,
    input  wire [23:0] I_rgb,
    input  wire [2:0]  I_ui_alpha,
    input  wire        I_panel_vis,   // 1=绘制设置面板（V2-12 前先接常量 1 观察外观）
    output wire        O_de,
    output wire        O_vs,
    output wire [23:0] O_rgb,
    output wire        rd_en,
    output wire [7:0]  rd_x,
    output wire [6:0]  rd_y,
    input  wire [1:0]  rd_data,
    // V2-15 百分比条输入
    input  wire [3:0]  I_bar_vol,
    input  wire [2:0]  I_bar_bri,
    input  wire [2:0]  I_bar_con,
    input  wire [2:0]  I_bar_sel     // 当前选中项 0~5（0=VOLUME）
);

    // ---------------- 底部横幅 + 状态栏文字（既有） ----------------
    localparam [10:0] OSD_X0 = 11'd304;   // V3: 右上角信息条
    localparam [9:0]  OSD_Y0 = 10'd8;
    localparam [10:0] OSD_W  = 11'd332;
    localparam [9:0]  OSD_H  = 10'd22;

    localparam [9:0]  TXT_Y0 = 10'd12;    // V3: 右上角
    localparam [10:0] TXT_X0 = 11'd312;
    localparam [10:0] TXT_X1 = 11'd632;

    // ---------------- 设置面板（V2-10） ----------------
    // 256px 宽 × 144px 高，屏幕正中：x 192~447、y 168~311
    localparam [10:0] PNL_X0 = 11'd160;
    localparam [9:0]  PNL_Y0 = 10'd168;
    localparam [10:0] PNL_W  = 11'd320;
    localparam [9:0]  PNL_H  = 10'd144;

    // 面板文字区：x 200~439（240px=120 buffer 列）、y 184~311（128px=64 buffer 行）
    localparam [10:0] PTX_X0 = 11'd168;
    localparam [10:0] PTX_X1 = 11'd472;
    localparam [9:0]  PTX_Y0 = 10'd176;
    // V2-14 字幕窗口（面板关闭时显示，x 272~361 / y 400~413）
    localparam [10:0] STX_X0 = 11'd64;
    localparam [10:0] STX_X1 = 11'd576;
    localparam [9:0]  STX_Y0 = 10'd400;
    localparam [9:0]  STX_Y1 = 10'd414;
    // 字幕底条（全宽半透明带，比文字区略大）
    localparam [10:0] SBX_X0 = 11'd56;
    localparam [10:0] SBX_X1 = 11'd584;
    localparam [9:0]  SBX_Y0 = 10'd394;
    localparam [9:0]  SBX_Y1 = 10'd418;
    localparam [9:0]  PTX_Y1 = 10'd304;

    localparam [23:0] BANNER_COLOR      = 24'h221A14;
    localparam [23:0] BANNER_EDGE_COLOR = 24'hC9A227;
    localparam [23:0] PANEL_COLOR       = 24'h1A1D23;
    localparam [23:0] BORDER_COLOR      = 24'hFFFFFF;
    localparam [23:0] TEXT_COLOR        = 24'hF4EDE2;
    localparam [23:0] HIGHLIGHT_COLOR   = 24'hE8A838;

    reg [10:0] x_cnt;
    reg [9:0]  y_cnt;
    reg        de_d;
    reg        vs_d;

    reg [23:0] rgb_q;
    reg        de_q;
    reg        vs_q;
    reg        bg_q;
    reg        edge_q;
    reg        sit_q;
    reg        text_q;
    reg        pnl_body_q;
    reg        pnl_border_q;
    reg        ptxt_q;
    reg        stxt_q;
    reg        stxt_bg_q;
    // V2-15 百分比条：位于名称与数值之间（buffer 列 64~127 → 屏幕 x 296~423）
    localparam [10:0] BAR_X0 = 11'd296;
    localparam [10:0] BAR_X1 = 11'd424;
    localparam [23:0] BAR_FILL_COLOR = 24'hEAF6FF;   // 近白填充（暗底与金黄底都清晰）
    reg        bar_area_q;
    reg        bar_fill_q;
    reg [2:0]  bar_line_q;

    wire [10:0] x_next = x_cnt + 11'd1;
    wire [9:0]  y_next = y_cnt + 10'd1;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            x_cnt <= 11'd0;
            y_cnt <= 10'd0;
            de_d  <= 1'b0;
            vs_d  <= 1'b0;
        end else begin
            de_d <= I_de;
            vs_d <= I_vs;
            if (vs_d != I_vs) begin
                x_cnt <= 11'd0;
                y_cnt <= 10'd0;
            end else if (I_de) begin
                x_cnt <= x_next;
            end else begin
                x_cnt <= 11'd0;
                if (de_d)
                    y_cnt <= y_next;
            end
        end
    end

    // ---------------- 窗口判定 ----------------
    wire bg_win = I_de
               && (x_cnt >= OSD_X0) && (x_cnt < (OSD_X0 + OSD_W))
               && (y_cnt >= OSD_Y0) && (y_cnt < (OSD_Y0 + OSD_H));
    wire edge_row = (y_cnt < (OSD_Y0 + 10'd2))
                  || (y_cnt >= (OSD_Y0 + OSD_H - 10'd2));

    // 2026/10/24 左上角信息条：与右上角同款底条（同色同边），几何不同
    // 左底条与右上角**同高同 y**（OSD_Y0=8、OSD_H=22），文字窗口内缩 4px
    localparam [10:0] SIT_X0 = 11'd8;
    localparam [10:0] SIT_X1 = 11'd144;
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
    wire [9:0]  sit_rel_y = y_cnt - (OSD_Y0 + 10'd4);
    wire text_win = I_de
                 && (x_cnt >= TXT_X0) && (x_cnt < TXT_X1)
                 && (y_cnt >= TXT_Y0) && (y_cnt < (TXT_Y0 + 10'd14));

    wire [10:0] txt_rel_x = x_cnt - TXT_X0;
    wire [9:0]  txt_rel_y = y_cnt - TXT_Y0;

    // 面板几何
    wire        pnl_win   = I_panel_vis && I_de
                          && (x_cnt >= PNL_X0) && (x_cnt < (PNL_X0 + PNL_W))
                          && (y_cnt >= PNL_Y0) && (y_cnt < (PNL_Y0 + PNL_H));
    wire [10:0] pnl_rel_x = x_cnt - PNL_X0;
    wire [9:0]  pnl_rel_y = y_cnt - PNL_Y0;

    // 4 个角各切掉 2×2 屏幕像素（≈8px 圆角）
    wire pnl_corner = ((pnl_rel_x < 11'd2) || (pnl_rel_x >= (PNL_W - 11'd2)))
                   && ((pnl_rel_y < 10'd2) || (pnl_rel_y >= (PNL_H - 10'd2)));

    // 1px 边框
    wire pnl_edge = (pnl_rel_x == 11'd0) || (pnl_rel_x == (PNL_W - 11'd1))
                 || (pnl_rel_y == 10'd0) || (pnl_rel_y == (PNL_H - 10'd1));

    wire pnl_body   = pnl_win && !pnl_corner && !pnl_edge;
    wire pnl_border = pnl_win && !pnl_corner &&  pnl_edge;

    // 面板文字区（V2-11 恢复）：x 200~439、y 184~311
    wire ptxt_win = I_panel_vis && I_de
                 && (x_cnt >= PTX_X0) && (x_cnt < PTX_X1)
                 && (y_cnt >= PTX_Y0) && (y_cnt < PTX_Y1);
    wire [10:0] ptxt_rel_x = x_cnt - PTX_X0;
    wire [9:0]  ptxt_rel_y = y_cnt - PTX_Y0;

    // V2-14 字幕窗口：面板关闭时才显示
    wire stxt_win    = 1'b0;   // 2026/10/25 旧点阵字幕停用（文字+底色一并关闭）
    wire stxt_bg_win = 1'b0;  // 2026/10/25 字幕底色停用
    wire [10:0] stxt_rel_x = x_cnt - STX_X0;
    wire [9:0]  stxt_rel_y = y_cnt - STX_Y0;

    // ---------------- V2-15 百分比条几何 ----------------
    // 三个数值项对应文字行的屏幕 y：行 r 的中心 = 176 + r*16
    wire bar_row_vol = (y_cnt >= 10'd196) && (y_cnt < 10'd203);
    wire bar_row_bri = (y_cnt >= 10'd212) && (y_cnt < 10'd219);
    wire bar_row_con = (y_cnt >= 10'd228) && (y_cnt < 10'd235);
    wire bar_x_ok    = (x_cnt >= BAR_X0) && (x_cnt < BAR_X1);
    wire bar_in      = I_panel_vis && I_de && bar_x_ok
                    && (bar_row_vol || bar_row_bri || bar_row_con);

    // 0 值不画填充；(v+1)*步进 保证最大值填满整条
    // 音量：v*8 + v/2（0,8,17..127 均匀步进，0 为空）
    wire [7:0] vol_px = {4'd0, I_bar_vol, 3'b000} + {5'd0, I_bar_vol[3:1]};
    // 亮度/对比度：v*32（0,32,64,96,128 完全均匀）
    wire [7:0] bri_px = {I_bar_bri, 5'b00000};
    wire [7:0] con_px = {I_bar_con, 5'b00000};
    wire [10:0] vol_end = BAR_X0 + {3'd0, vol_px};
    wire [10:0] bri_end = BAR_X0 + {3'd0, bri_px};
    wire [10:0] con_end = BAR_X0 + {3'd0, con_px};

    wire bar_fill = bar_row_vol ? (x_cnt < vol_end) :
                    bar_row_bri ? (x_cnt < bri_end) :
                                  (x_cnt < con_end);
    wire [2:0] bar_line = bar_row_vol ? 3'd1 : bar_row_bri ? 3'd2 : 3'd3;
    // 读地址：面板文字 > 字幕 > 状态栏
    assign rd_en = text_win || sit_win || ptxt_win || stxt_win;
    assign rd_x  = sit_win  ? (8'd160 + sit_rel_x[8:1]) :
                   ptxt_win ? ptxt_rel_x[8:1] :
                   stxt_win ? stxt_rel_x[8:1] :
                              txt_rel_x[8:1];
    assign rd_y  = sit_win  ? (7'd72 + {1'b0, sit_rel_y[4:1]}) :
                   ptxt_win ? (7'd8 + {1'b0, ptxt_rel_y[6:1]}) :
                   stxt_win ? ({4'd0, stxt_rel_y[3:1]}) :      // 字幕存储行 0~6（见 subtitle_render）
                              (7'd72 + {1'b0, txt_rel_y[4:1]});

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            rgb_q        <= 24'd0;
            de_q         <= 1'b0;
            vs_q         <= 1'b0;
            bg_q         <= 1'b0;
            edge_q       <= 1'b0;
            sit_q        <= 1'b0;
            text_q       <= 1'b0;
            pnl_body_q   <= 1'b0;
            pnl_border_q <= 1'b0;
            ptxt_q       <= 1'b0;
            stxt_q       <= 1'b0;
            stxt_bg_q    <= 1'b0;
            bar_area_q   <= 1'b0;
            bar_fill_q   <= 1'b0;
            bar_line_q   <= 3'd0;
        end else begin
            rgb_q        <= I_rgb;
            de_q         <= I_de;
            vs_q         <= I_vs;
            bg_q         <= bg_any;
            edge_q       <= bg_any & edge_any;
            sit_q        <= sit_win;
            text_q       <= text_win;
            pnl_body_q   <= pnl_body;
            pnl_border_q <= pnl_border;
            ptxt_q       <= ptxt_win;
            stxt_q       <= stxt_win;
            stxt_bg_q    <= stxt_bg_win;
            bar_area_q   <= bar_in;
            bar_fill_q   <= bar_fill;
            bar_line_q   <= bar_line;
        end
    end

    function signed [12:0] mul_a;
        input signed [8:0] d;
        input [3:0]        a;
        reg signed [12:0]  p;
        begin
            p = 13'sd0;
            if (a[0]) p = p + d;
            if (a[1]) p = p + (d <<< 1);
            if (a[2]) p = p + (d <<< 2);
            if (a[3]) p = p + (d <<< 3);
            mul_a = p;
        end
    endfunction

    function [7:0] mix_a;
        input [7:0] bg;
        input [7:0] fg;
        input [3:0] a;
        reg signed [8:0]  d;
        reg signed [12:0] p;
        reg signed [10:0] p8;
        reg signed [10:0] s;
        begin
            d  = {1'b0, fg} - {1'b0, bg};
            p  = mul_a(d, a);
            p8 = p >>> 3;
            s  = {3'b0, bg} + p8;
            if (s[10])
                mix_a = 8'd0;
            else if (s[9])
                mix_a = 8'd255;
            else
                mix_a = s[7:0];
        end
    endfunction

    function [7:0] mix75;
        input [7:0] bg;
        input [7:0] fg;
        reg [11:0] v;
        begin
            v = {4'd0, fg} + {3'd0, fg, 1'b0} + {4'd0, bg};
            mix75 = v[9:2];
        end
    endfunction

    function [7:0] mix50;
        input [7:0] bg;
        input [7:0] fg;
        reg [8:0] v;
        begin
            v = {1'b0, bg} + {1'b0, fg};
            mix50 = v[8:1];
        end
    endfunction

    function [7:0] mix35;
        input [7:0] bg;
        input [7:0] fg;
        reg [11:0] v;
        begin
            v = {4'd0, fg} + {3'd0, fg, 1'b0}
              + {4'd0, bg} + {2'd0, bg, 2'b00};
            mix35 = v[10:3];
        end
    endfunction

    wire [3:0] a_int = (I_ui_alpha == 3'd7) ? 4'd8 : {1'b0, I_ui_alpha};

    // ---------------- 横幅层次（既有） ----------------
    wire [23:0] bg_fg = edge_q ? BANNER_EDGE_COLOR : BANNER_COLOR;
    wire [23:0] bg_layer = {
        mix_a(rgb_q[23:16], bg_fg[23:16], a_int),
        mix_a(rgb_q[15:8],  bg_fg[15:8],  a_int),
        mix_a(rgb_q[7:0],   bg_fg[7:0],   a_int)
    };

    wire [23:0] layer01 = {
        mix75(bg_layer[23:16], PANEL_COLOR[23:16]),
        mix75(bg_layer[15:8],  PANEL_COLOR[15:8]),
        mix75(bg_layer[7:0],   PANEL_COLOR[7:0])
    };
    wire [23:0] layer11 = {
        mix35(bg_layer[23:16], HIGHLIGHT_COLOR[23:16]),
        mix35(bg_layer[15:8],  HIGHLIGHT_COLOR[15:8]),
        mix35(bg_layer[7:0],   HIGHLIGHT_COLOR[7:0])
    };

    wire [1:0]  typ = text_q ? rd_data : 2'b00;
    wire [23:0] fg_layer = (typ == 2'b10) ? TEXT_COLOR :
                           (typ == 2'b01) ? layer01 :
                           (typ == 2'b11) ? layer11 : bg_layer;

    wire [23:0] blend_rgb = {
        mix_a(bg_layer[23:16], fg_layer[23:16], a_int),
        mix_a(bg_layer[15:8],  fg_layer[15:8],  a_int),
        mix_a(bg_layer[7:0],   fg_layer[7:0],   a_int)
    };

    // ---------------- 面板层次（V2-10） ----------------
    // 2026/10/21：用户反馈 75% 偏深，改为 50% 混合
    wire [23:0] pnl_bg_rgb = {
        mix50(rgb_q[23:16], PANEL_COLOR[23:16]),
        mix50(rgb_q[15:8],  PANEL_COLOR[15:8]),
        mix50(rgb_q[7:0],   PANEL_COLOR[7:0])
    };
    // 边框 alpha 1/8：用移位近似 (rgb*7 + 255)/8，省掉 mix_a 的乘法链
    function [7:0] mix8;
        input [7:0] bg;
        begin
            mix8 = ({1'b0, bg, 3'b000} + {1'b0, bg, 2'b00} + {1'b0, bg, 1'b0} + bg + 9'd255) >> 4;
        end
    endfunction
    wire [23:0] pnl_bd_rgb = {
        mix8(rgb_q[23:16]),
        mix8(rgb_q[15:8]),
        mix8(rgb_q[7:0])
    };

    // 面板文字层：typ=10 文字色、typ=11 琥珀高亮块、其余（含未写像素）显示面板底
    // 高亮直接用琥珀色（不混合），省掉 3 通道 mix35 的面积
    // 2026/10/22：选中行改为「金黄底 + 深灰字」（用户与另一代理确认的配色）
    localparam [23:0] HL_BG_COLOR   = 24'hC4A447;   // 金黄
    localparam [23:0] HL_TEXT_COLOR = 24'h1A1D23;   // 深灰
    wire [23:0] pnl_hl_rgb = HL_BG_COLOR;
    // typ: 10=普通文字(米白) 01=高亮行文字(深灰) 11=高亮底(金黄) 其余=面板底
    wire [23:0] pnl_txt_rgb = !ptxt_q          ? pnl_bg_rgb :
                              (rd_data == 2'b10) ? TEXT_COLOR :
                              (rd_data == 2'b01) ? HL_TEXT_COLOR :
                              (rd_data == 2'b11) ? pnl_hl_rgb : pnl_bg_rgb;
    // V2-15 百分比条：填充近白，空槽 = 该行背景压暗 50%（与高亮底协调）
    wire bar_sel_now = (bar_line_q == ({1'b0, I_bar_sel} + 4'd1));
    wire [23:0] bar_bg = bar_sel_now ? HL_BG_COLOR : pnl_bg_rgb;
    wire [23:0] bar_track_rgb = {1'b0, bar_bg[23:17], 1'b0, bar_bg[15:9], 1'b0, bar_bg[7:1]};
    wire [23:0] bar_rgb = bar_fill_q ? BAR_FILL_COLOR : bar_track_rgb;

    wire [23:0] pnl_out = pnl_border_q ? pnl_bd_rgb :
                          pnl_body_q   ? (bar_area_q ? bar_rgb : pnl_txt_rgb) : rgb_q;

    assign O_de  = de_q;
    assign O_vs  = vs_q;
    // V2-14 字幕层：白字 + 半透明深色底条（保证浅色图片上也能看清）
    wire [23:0] sub_bar_rgb = {
        mix50(rgb_q[23:16], 8'h14),
        mix50(rgb_q[15:8],  8'h18),
        mix50(rgb_q[7:0],   8'h1C)
    };
    wire [23:0] sub_rgb = (stxt_q && (rd_data == 2'b10)) ? TEXT_COLOR :
                          stxt_bg_q ? sub_bar_rgb : rgb_q;

    // 左上角信息条文字：底条走 bg 支路，文字用暖白色
    wire sit_txt = sit_q && (rd_data == 2'b10);
    assign O_rgb = bg_q ? (sit_txt ? TEXT_COLOR : blend_rgb) :
                   (stxt_q || stxt_bg_q) ? sub_rgb : pnl_out;

endmodule
