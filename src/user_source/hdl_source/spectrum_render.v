// 频谱条渲染（V4.2）：40 根条（12px 条 + 4px 缝），线性高度
module spectrum_render (
    input  wire         I_clk,
    input  wire         I_rst,
    input  wire         I_vs,
    input  wire         I_de,
    input  wire [9:0]   I_x,
    input  wire [9:0]   I_y,
    input  wire [23:0]  I_rgb,
    input  wire [239:0] I_bands,
    input  wire [1:0]   I_emph_lvl,
    output reg          O_vs,
    output reg          O_de,
    output reg  [23:0]  O_rgb
);
    localparam [9:0] BASE = 10'd479;      // 2026-10-31：贴到画面最底一行

    reg [5:0] band_h;
    always @(*) begin
        case (I_x[9:4])
            6'd 0: band_h = I_bands[  0 +: 6];
            6'd 1: band_h = I_bands[  6 +: 6];
            6'd 2: band_h = I_bands[ 12 +: 6];
            6'd 3: band_h = I_bands[ 18 +: 6];
            6'd 4: band_h = I_bands[ 24 +: 6];
            6'd 5: band_h = I_bands[ 30 +: 6];
            6'd 6: band_h = I_bands[ 36 +: 6];
            6'd 7: band_h = I_bands[ 42 +: 6];
            6'd 8: band_h = I_bands[ 48 +: 6];
            6'd 9: band_h = I_bands[ 54 +: 6];
            6'd10: band_h = I_bands[ 60 +: 6];
            6'd11: band_h = I_bands[ 66 +: 6];
            6'd12: band_h = I_bands[ 72 +: 6];
            6'd13: band_h = I_bands[ 78 +: 6];
            6'd14: band_h = I_bands[ 84 +: 6];
            6'd15: band_h = I_bands[ 90 +: 6];
            6'd16: band_h = I_bands[ 96 +: 6];
            6'd17: band_h = I_bands[102 +: 6];
            6'd18: band_h = I_bands[108 +: 6];
            6'd19: band_h = I_bands[114 +: 6];
            6'd20: band_h = I_bands[120 +: 6];
            6'd21: band_h = I_bands[126 +: 6];
            6'd22: band_h = I_bands[132 +: 6];
            6'd23: band_h = I_bands[138 +: 6];
            6'd24: band_h = I_bands[144 +: 6];
            6'd25: band_h = I_bands[150 +: 6];
            6'd26: band_h = I_bands[156 +: 6];
            6'd27: band_h = I_bands[162 +: 6];
            6'd28: band_h = I_bands[168 +: 6];
            6'd29: band_h = I_bands[174 +: 6];
            6'd30: band_h = I_bands[180 +: 6];
            6'd31: band_h = I_bands[186 +: 6];
            6'd32: band_h = I_bands[192 +: 6];
            6'd33: band_h = I_bands[198 +: 6];
            6'd34: band_h = I_bands[204 +: 6];
            6'd35: band_h = I_bands[210 +: 6];
            6'd36: band_h = I_bands[216 +: 6];
            6'd37: band_h = I_bands[222 +: 6];
            6'd38: band_h = I_bands[228 +: 6];
            6'd39: band_h = I_bands[234 +: 6];
            default: band_h = I_bands[234 +: 6];
        endcase
    end

    wire [5:0] bidx = I_x[9:4];

    reg        vs_q;
    reg  [1:0] fcnt;
    reg  [5:0] eph;
    wire       vs_rise = I_vs & ~vs_q;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            vs_q <= 1'b0; fcnt <= 2'd0; eph <= 6'd0;
        end else begin
            vs_q <= I_vs;
            if (vs_rise) begin
                if (fcnt == 2'd2) begin
                    fcnt <= 2'd0;
                    eph  <= (eph == 6'd39) ? 6'd0 : (eph + 6'd1);
                end else fcnt <= fcnt + 2'd1;
            end
        end
    end

    wire [5:0] bdist = (bidx > eph) ? (bidx - eph) : (eph - bidx);
    wire [5:0] cw    = (bdist >= 6'd8) ? 6'd0 : (6'd8 - bdist);
    wire [5:0] crest = (I_emph_lvl == 2'd0) ? 6'd0 :
                       (I_emph_lvl == 2'd1) ? (cw >> 1) :
                       (I_emph_lvl == 2'd2) ? ((cw >> 1) + (cw >> 2)) :
                                              cw;
    wire [6:0] hsum   = {1'b0, band_h} + {1'b0, crest};
    wire [5:0] band_he = (band_h == 6'd0)   ? 6'd0 :
                         (hsum > 7'd63)     ? 6'd63 : hsum[5:0];

    // 2026-10-31：只把基线移到画面最底一行（y=479），高度与配色保持原样
    wire [9:0] bar_top  = BASE - {4'd0, band_he};
    wire       in_strip = (I_x[3:0] < 4'd12);
    wire       in_area  = I_de && in_strip && (I_y <= BASE) && (I_y >= (BASE - 10'd64));
    wire       bar_on   = in_area && (band_he != 6'd0) && (I_y >= bar_top);
    wire       cap_on   = bar_on && (I_y < (bar_top + 10'd2));
    wire       base_on  = I_de && (I_y == BASE);

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            O_vs <= 1'b0; O_de <= 1'b0; O_rgb <= 24'd0;
        end else begin
            O_vs <= I_vs;
            O_de <= I_de;
            if (cap_on)        O_rgb <= 24'hFFE8F5;
            else if (bar_on)   O_rgb <= 24'hE8458F;
            else if (base_on)  O_rgb <= 24'hFFB3D9;
            else               O_rgb <= I_rgb;
        end
    end
endmodule
