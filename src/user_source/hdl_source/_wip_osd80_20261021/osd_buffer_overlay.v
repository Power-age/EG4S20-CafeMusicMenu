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
    input  wire [1:0]  rd_data
);

    // ---------------- 底部横幅 + 状态栏文字（既有） ----------------
    localparam [10:0] OSD_X0 = 11'd0;
    localparam [9:0]  OSD_Y0 = 10'd432;
    localparam [10:0] OSD_W  = 11'd640;
    localparam [9:0]  OSD_H  = 10'd40;

    localparam [9:0]  TXT_Y0 = 10'd444;
    localparam [10:0] TXT_X0 = 11'd64;
    localparam [10:0] TXT_X1 = 11'd576;

    // ---------------- 设置面板（V2-10） ----------------
    // 256px 宽 × 144px 高，屏幕正中：x 192~447、y 168~311
    localparam [10:0] PNL_X0 = 11'd192;
    localparam [9:0]  PNL_Y0 = 10'd168;
    localparam [10:0] PNL_W  = 11'd256;
    localparam [9:0]  PNL_H  = 10'd144;

    // 面板文字区：x 200~439（240px=120 buffer 列）、y 184~311（128px=64 buffer 行）
    localparam [10:0] PTX_X0 = 11'd200;
    localparam [10:0] PTX_X1 = 11'd440;
    localparam [9:0]  PTX_Y0 = 10'd184;
    localparam [9:0]  PTX_Y1 = 10'd312;

    localparam [23:0] BANNER_COLOR      = 24'h101820;
    localparam [23:0] BANNER_EDGE_COLOR = 24'h00D0FF;
    localparam [23:0] PANEL_COLOR       = 24'h1A1D23;
    localparam [23:0] BORDER_COLOR      = 24'hFFFFFF;
    localparam [23:0] TEXT_COLOR        = 24'hF0EDE8;
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
    reg        text_q;
    reg        pnl_body_q;
    reg        pnl_border_q;

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
    wire text_win = I_de
                 && (x_cnt >= TXT_X0) && (x_cnt < TXT_X1)
                 && (y_cnt >= TXT_Y0) && (y_cnt < (TXT_Y0 + 10'd16));

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

    // 读地址（V2-10 只有状态栏用；面板文字在 V2-11 接入）
    assign rd_en = text_win;
    assign rd_x  = txt_rel_x[8:1];
    assign rd_y  = 7'd72 + {1'b0, txt_rel_y[4:1]};

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            rgb_q        <= 24'd0;
            de_q         <= 1'b0;
            vs_q         <= 1'b0;
            bg_q         <= 1'b0;
            edge_q       <= 1'b0;
            text_q       <= 1'b0;
            pnl_body_q   <= 1'b0;
            pnl_border_q <= 1'b0;
        end else begin
            rgb_q        <= I_rgb;
            de_q         <= I_de;
            vs_q         <= I_vs;
            bg_q         <= bg_win;
            edge_q       <= bg_win & edge_row;
            text_q       <= text_win;
            pnl_body_q   <= pnl_body;
            pnl_border_q <= pnl_border;
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
    wire [23:0] pnl_bg_rgb = {
        mix75(rgb_q[23:16], PANEL_COLOR[23:16]),
        mix75(rgb_q[15:8],  PANEL_COLOR[15:8]),
        mix75(rgb_q[7:0],   PANEL_COLOR[7:0])
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

    wire [23:0] pnl_out = pnl_border_q ? pnl_bd_rgb :
                          pnl_body_q   ? pnl_bg_rgb : rgb_q;

    assign O_de  = de_q;
    assign O_vs  = vs_q;
    assign O_rgb = bg_q ? blend_rgb : pnl_out;

endmodule
