// 视频像素效果层（V2-13 精简版）
//
// 从 video_osd_overlay.v 提取「像素处理」部分，去掉信息栏文字与字模表：
//   ① 亮度  brightness_channel()   —— 4 档，作用在通道高 3 位
//   ② 对比度 contrast_channel()    —— 4 档
//   ③ 转场  reveal 扫边 + 遮罩     —— wipe（揭幕）时按 x 坐标逐像素合成
//   ④ 淡入淡出 fade_channel()      —— fade 模式下的黑场过渡
//
// 原模块里 90% 的面积是 30 个字符的手绘字模与面板区域判断，本模块不包含。
module video_effect_overlay (
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_vs,
    input  wire        I_de,
    input  wire [23:0] I_rgb,
    input  wire [2:0]  I_brightness_level,
    input  wire [2:0]  I_contrast_level,
    input  wire [2:0]  I_fade_level,
    input  wire        I_transition_active,
    input  wire [9:0]  I_transition_reveal_x,
    output wire [23:0] O_rgb
);

    localparam [23:0] TRANSITION_MASK_COLOR = 24'h000000;
    localparam [23:0] TRANSITION_EDGE0_COLOR = 24'h303030;
    localparam [23:0] TRANSITION_EDGE1_COLOR = 24'h202020;
    localparam [23:0] TRANSITION_EDGE2_COLOR = 24'h101010;
    localparam [23:0] TRANSITION_EDGE3_COLOR = 24'h080808;
    localparam [5:0]  TRANSITION_SOFT_WIDTH = 6'd32;

    // 亮度：5 档（0=最暗 2=正常 4=最亮），作用于通道高 4 位
    function [7:0] brightness_channel;
        input [7:0] channel;
        input [2:0] level;
        reg [4:0] hi;
        reg [4:0] off;
        begin
            hi  = {1'b0, channel[7:4]};
            off = {2'b00, level};
            if (off >= 5'd2) begin
                hi = hi + (off - 5'd2);
                if (hi > 5'd15) hi = 5'd15;
            end else begin
                hi = hi - (5'd2 - off);
                if (hi > 5'd15) hi = 5'd0;   // 借位 => 下溢，钳到 0
            end
            brightness_channel = {hi[3:0], channel[3:0]};
        end
    endfunction

    // 对比度：5 档（0=最弱 2=原图 4=最强），围绕中灰 ±缩放
    function [7:0] contrast_channel;
        input [7:0] channel;
        input [2:0] level;
        reg signed [8:0] d;
        reg signed [10:0] r;
        begin
            d = $signed({1'b0, channel}) - 9'sd128;
            case (level)
                3'd0: r = d >>> 2;
                3'd1: r = d >>> 1;
                3'd2: r = d;
                3'd3: r = d + (d >>> 1);
                3'd4: r = d <<< 1;
                default: r = d;
            endcase
            r = r + 11'sd128;
            if (r < 11'sd0)
                contrast_channel = 8'd0;
            else if (r > 11'sd255)
                contrast_channel = 8'hFF;
            else
                contrast_channel = r[7:0];
        end
    endfunction
    function [7:0] fade_channel;
        input [7:0] channel;
        input [2:0] level;
        begin
            case (level)
                3'd1: fade_channel = (channel >> 1) + (channel >> 2);
                3'd2: fade_channel = channel >> 1;
                3'd3: fade_channel = channel >> 2;
                3'd4: fade_channel = 8'd0;
                default: fade_channel = channel;
            endcase
        end
    endfunction

    // ---------------- 输入打两拍，与像素对齐 ----------------
    reg [2:0] bright_s1, bright_s2;
    reg [2:0] contrast_s1, contrast_s2;
    reg [2:0] fade_s1, fade_s2;
    reg       tactive_s1, tactive_s2;
    reg [9:0] reveal_s1, reveal_s2;
    reg       de_d, vs_d;
    reg [10:0] x_cnt;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            bright_s1   <= 3'd2;  bright_s2   <= 3'd2;
            contrast_s1 <= 3'd2;  contrast_s2 <= 3'd2;
            fade_s1     <= 3'd0;  fade_s2     <= 3'd0;
            tactive_s1  <= 1'b0;  tactive_s2  <= 1'b0;
            reveal_s1   <= 10'd640; reveal_s2 <= 10'd640;
            de_d        <= 1'b0;
            vs_d        <= 1'b0;
            x_cnt       <= 11'd0;
        end else begin
            bright_s1   <= I_brightness_level;
            bright_s2   <= bright_s1;
            contrast_s1 <= I_contrast_level;
            contrast_s2 <= contrast_s1;
            fade_s1     <= I_fade_level;
            fade_s2     <= fade_s1;
            tactive_s1  <= I_transition_active;
            tactive_s2  <= tactive_s1;
            reveal_s1   <= I_transition_reveal_x;
            reveal_s2   <= reveal_s1;
            de_d        <= I_de;
            vs_d        <= I_vs;

            if (vs_d != I_vs)
                x_cnt <= 11'd0;
            else if (I_de) begin
                if (!de_d)
                    x_cnt <= 11'd0;
                else
                    x_cnt <= x_cnt + 11'd1;
            end else
                x_cnt <= 11'd0;
        end
    end

    // ---------------- 亮度 → 对比度 ----------------
    wire [23:0] brightness_rgb = {
        brightness_channel(I_rgb[23:16], bright_s2),
        brightness_channel(I_rgb[15:8],  bright_s2),
        brightness_channel(I_rgb[7:0],   bright_s2)
    };
    wire [23:0] adjusted_rgb = {
        contrast_channel(brightness_rgb[23:16], contrast_s2),
        contrast_channel(brightness_rgb[15:8],  contrast_s2),
        contrast_channel(brightness_rgb[7:0],   contrast_s2)
    };

    // ---------------- 转场（揭幕扫边 + 遮罩） ----------------
    wire [10:0] rx       = {1'b0, reveal_s2};
    wire [10:0] e1       = rx + 11'd8;
    wire [10:0] e2       = rx + 11'd16;
    wire [10:0] e3       = rx + 11'd24;
    wire [10:0] e4       = rx + {5'd0, TRANSITION_SOFT_WIDTH};

    wire edge0_area = tactive_s2 && I_de && (x_cnt >= rx) && (x_cnt < e1);
    wire edge1_area = tactive_s2 && I_de && (x_cnt >= e1) && (x_cnt < e2);
    wire edge2_area = tactive_s2 && I_de && (x_cnt >= e2) && (x_cnt < e3);
    wire edge3_area = tactive_s2 && I_de && (x_cnt >= e3) && (x_cnt < e4);
    wire mask_area  = tactive_s2 && I_de && (x_cnt >= e4);

    wire [23:0] transition_rgb = mask_area  ? TRANSITION_MASK_COLOR :
                                 edge3_area ? TRANSITION_EDGE3_COLOR :
                                 edge2_area ? TRANSITION_EDGE2_COLOR :
                                 edge1_area ? TRANSITION_EDGE1_COLOR :
                                 edge0_area ? TRANSITION_EDGE0_COLOR :
                                              adjusted_rgb;

    // ---------------- 淡入淡出 ----------------
    assign O_rgb = {
        fade_channel(transition_rgb[23:16], fade_s2),
        fade_channel(transition_rgb[15:8],  fade_s2),
        fade_channel(transition_rgb[7:0],   fade_s2)
    };

endmodule
