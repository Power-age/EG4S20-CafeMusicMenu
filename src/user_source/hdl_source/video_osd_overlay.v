module video_osd_overlay(
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_enable,
    input  wire        I_vs,
    input  wire        I_de,
    input  wire [23:0] I_rgb,
    input  wire [3:0]  I_state_code,
    input  wire        I_auto_play_en,
    input  wire [1:0]  I_brightness_level,
    input  wire [1:0]  I_contrast_level,
    input  wire        I_param_default_en,
    input  wire        I_transition_active,
    input  wire [9:0]  I_transition_reveal_x,
    input  wire [2:0]  I_fade_level,
    output wire [23:0] O_rgb
);

localparam [23:0] PANEL_COLOR  = 24'h182838;
localparam [23:0] BORDER_COLOR = 24'h00D0FF;
localparam [23:0] TEXT_COLOR   = 24'hFFE060;
localparam [23:0] TRANSITION_MASK_COLOR = 24'h000000;
localparam [23:0] TRANSITION_EDGE0_COLOR = 24'h303030;
localparam [23:0] TRANSITION_EDGE1_COLOR = 24'h202020;
localparam [23:0] TRANSITION_EDGE2_COLOR = 24'h101010;
localparam [23:0] TRANSITION_EDGE3_COLOR = 24'h080808;
localparam [5:0]  TRANSITION_SOFT_WIDTH = 6'd32;

function [7:0] hex_char;
    input [3:0] value;
    begin
        case (value)
            4'h0: hex_char = 8'h30;
            4'h1: hex_char = 8'h31;
            4'h2: hex_char = 8'h32;
            4'h3: hex_char = 8'h33;
            4'h4: hex_char = 8'h34;
            4'h5: hex_char = 8'h35;
            4'h6: hex_char = 8'h36;
            4'h7: hex_char = 8'h37;
            4'h8: hex_char = 8'h38;
            4'h9: hex_char = 8'h39;
            4'hA: hex_char = 8'h41;
            4'hB: hex_char = 8'h42;
            4'hC: hex_char = 8'h43;
            4'hD: hex_char = 8'h44;
            4'hE: hex_char = 8'h45;
            default: hex_char = 8'h46;
        endcase
    end
endfunction

function [7:0] line0_char;
    input [3:0] index;
    begin
        case (index)
            4'd0: line0_char = 8'h41;
            4'd1: line0_char = 8'h4E;
            4'd2: line0_char = 8'h4C;
            4'd3: line0_char = 8'h55;
            4'd4: line0_char = 8'h20;
            4'd5: line0_char = 8'h48;
            4'd6: line0_char = 8'h44;
            4'd7: line0_char = 8'h4D;
            4'd8: line0_char = 8'h49;
            default: line0_char = 8'h20;
        endcase
    end
endfunction

function [7:0] line1_char;
    input [3:0] index;
    input [3:0] state_code;
    begin
        case (index)
            4'd0: line1_char = 8'h53;
            4'd1: line1_char = 8'h44;
            4'd2: line1_char = 8'h3A;
            4'd3: line1_char = hex_char(state_code);
            default: line1_char = 8'h20;
        endcase
    end
endfunction

function [7:0] line2_char;
    input [3:0] index;
    input       auto_play_en;
    begin
        case (index)
            4'd0: line2_char = 8'h41;
            4'd1: line2_char = 8'h55;
            4'd2: line2_char = 8'h54;
            4'd3: line2_char = 8'h4F;
            4'd4: line2_char = 8'h3A;
            4'd5: line2_char = 8'h4F;
            4'd6: line2_char = auto_play_en ? 8'h4E : 8'h46;
            4'd7: line2_char = auto_play_en ? 8'h20 : 8'h46;
            default: line2_char = 8'h20;
        endcase
    end
endfunction

function [7:0] line3_char;
    input [3:0] index;
    input [1:0] brightness_level;
    begin
        case (index)
            4'd0: line3_char = 8'h42;
            4'd1: line3_char = 8'h52;
            4'd2: line3_char = 8'h49;
            4'd3: line3_char = 8'h3A;
            4'd4: line3_char = hex_char({2'b00, brightness_level});
            default: line3_char = 8'h20;
        endcase
    end
endfunction

function [7:0] line4_char;
    input [3:0] index;
    input [1:0] contrast_level;
    begin
        case (index)
            4'd0: line4_char = 8'h43;
            4'd1: line4_char = 8'h4F;
            4'd2: line4_char = 8'h4E;
            4'd3: line4_char = 8'h3A;
            4'd4: line4_char = hex_char({2'b00, contrast_level});
            default: line4_char = 8'h20;
        endcase
    end
endfunction

function [4:0] glyph_row;
    input [7:0] code;
    input [2:0] row;
    begin
        case (code)
            8'h30: begin
                case (row)
                    3'd0: glyph_row = 5'b01110;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b10011;
                    3'd3: glyph_row = 5'b10101;
                    3'd4: glyph_row = 5'b11001;
                    3'd5: glyph_row = 5'b10001;
                    3'd6: glyph_row = 5'b01110;
                    default: glyph_row = 5'b00000;
                endcase
            end
            8'h31: begin
                case (row)
                    3'd0: glyph_row = 5'b00100;
                    3'd1: glyph_row = 5'b01100;
                    3'd2: glyph_row = 5'b00100;
                    3'd3: glyph_row = 5'b00100;
                    3'd4: glyph_row = 5'b00100;
                    3'd5: glyph_row = 5'b00100;
                    3'd6: glyph_row = 5'b01110;
                    default: glyph_row = 5'b00000;
                endcase
            end
            8'h32: begin
                case (row)
                    3'd0: glyph_row = 5'b01110;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b00001;
                    3'd3: glyph_row = 5'b00010;
                    3'd4: glyph_row = 5'b00100;
                    3'd5: glyph_row = 5'b01000;
                    3'd6: glyph_row = 5'b11111;
                    default: glyph_row = 5'b00000;
                endcase
            end
            8'h33: begin
                case (row)
                    3'd0: glyph_row = 5'b11110;
                    3'd1: glyph_row = 5'b00001;
                    3'd2: glyph_row = 5'b00001;
                    3'd3: glyph_row = 5'b01110;
                    3'd4: glyph_row = 5'b00001;
                    3'd5: glyph_row = 5'b00001;
                    3'd6: glyph_row = 5'b11110;
                    default: glyph_row = 5'b00000;
                endcase
            end
            8'h34: begin
                case (row)
                    3'd0: glyph_row = 5'b00010;
                    3'd1: glyph_row = 5'b00110;
                    3'd2: glyph_row = 5'b01010;
                    3'd3: glyph_row = 5'b10010;
                    3'd4: glyph_row = 5'b11111;
                    3'd5: glyph_row = 5'b00010;
                    3'd6: glyph_row = 5'b00010;
                    default: glyph_row = 5'b00000;
                endcase
            end
            8'h35: begin
                case (row)
                    3'd0: glyph_row = 5'b11111;
                    3'd1: glyph_row = 5'b10000;
                    3'd2: glyph_row = 5'b10000;
                    3'd3: glyph_row = 5'b11110;
                    3'd4: glyph_row = 5'b00001;
                    3'd5: glyph_row = 5'b00001;
                    3'd6: glyph_row = 5'b11110;
                    default: glyph_row = 5'b00000;
                endcase
            end
            8'h36: begin
                case (row)
                    3'd0: glyph_row = 5'b01110;
                    3'd1: glyph_row = 5'b10000;
                    3'd2: glyph_row = 5'b10000;
                    3'd3: glyph_row = 5'b11110;
                    3'd4: glyph_row = 5'b10001;
                    3'd5: glyph_row = 5'b10001;
                    3'd6: glyph_row = 5'b01110;
                    default: glyph_row = 5'b00000;
                endcase
            end
            8'h37: begin
                case (row)
                    3'd0: glyph_row = 5'b11111;
                    3'd1: glyph_row = 5'b00001;
                    3'd2: glyph_row = 5'b00010;
                    3'd3: glyph_row = 5'b00100;
                    3'd4: glyph_row = 5'b01000;
                    3'd5: glyph_row = 5'b01000;
                    3'd6: glyph_row = 5'b01000;
                    default: glyph_row = 5'b00000;
                endcase
            end
            8'h38: begin
                case (row)
                    3'd0: glyph_row = 5'b01110;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b10001;
                    3'd3: glyph_row = 5'b01110;
                    3'd4: glyph_row = 5'b10001;
                    3'd5: glyph_row = 5'b10001;
                    3'd6: glyph_row = 5'b01110;
                    default: glyph_row = 5'b00000;
                endcase
            end
            8'h39: begin
                case (row)
                    3'd0: glyph_row = 5'b01110;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b10001;
                    3'd3: glyph_row = 5'b01111;
                    3'd4: glyph_row = 5'b00001;
                    3'd5: glyph_row = 5'b00001;
                    3'd6: glyph_row = 5'b01110;
                    default: glyph_row = 5'b00000;
                endcase
            end
            8'h41: begin
                case (row)
                    3'd0: glyph_row = 5'b01110;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b10001;
                    3'd3: glyph_row = 5'b11111;
                    3'd4: glyph_row = 5'b10001;
                    3'd5: glyph_row = 5'b10001;
                    3'd6: glyph_row = 5'b10001;
                    default: glyph_row = 5'b00000;
                endcase
            end
            8'h42: begin
                case (row)
                    3'd0: glyph_row = 5'b11110;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b10001;
                    3'd3: glyph_row = 5'b11110;
                    3'd4: glyph_row = 5'b10001;
                    3'd5: glyph_row = 5'b10001;
                    3'd6: glyph_row = 5'b11110;
                    default: glyph_row = 5'b00000;
                endcase
            end
            8'h43: begin
                case (row)
                    3'd0: glyph_row = 5'b01110;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b10000;
                    3'd3: glyph_row = 5'b10000;
                    3'd4: glyph_row = 5'b10000;
                    3'd5: glyph_row = 5'b10001;
                    3'd6: glyph_row = 5'b01110;
                    default: glyph_row = 5'b00000;
                endcase
            end
            8'h44: begin
                case (row)
                    3'd0: glyph_row = 5'b11110;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b10001;
                    3'd3: glyph_row = 5'b10001;
                    3'd4: glyph_row = 5'b10001;
                    3'd5: glyph_row = 5'b10001;
                    3'd6: glyph_row = 5'b11110;
                    default: glyph_row = 5'b00000;
                endcase
            end
            8'h45: begin
                case (row)
                    3'd0: glyph_row = 5'b11111;
                    3'd1: glyph_row = 5'b10000;
                    3'd2: glyph_row = 5'b10000;
                    3'd3: glyph_row = 5'b11110;
                    3'd4: glyph_row = 5'b10000;
                    3'd5: glyph_row = 5'b10000;
                    3'd6: glyph_row = 5'b11111;
                    default: glyph_row = 5'b00000;
                endcase
            end
            8'h46: begin
                case (row)
                    3'd0: glyph_row = 5'b11111;
                    3'd1: glyph_row = 5'b10000;
                    3'd2: glyph_row = 5'b10000;
                    3'd3: glyph_row = 5'b11110;
                    3'd4: glyph_row = 5'b10000;
                    3'd5: glyph_row = 5'b10000;
                    3'd6: glyph_row = 5'b10000;
                    default: glyph_row = 5'b00000;
                endcase
            end
            8'h48: begin
                case (row)
                    3'd0: glyph_row = 5'b10001;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b10001;
                    3'd3: glyph_row = 5'b11111;
                    3'd4: glyph_row = 5'b10001;
                    3'd5: glyph_row = 5'b10001;
                    3'd6: glyph_row = 5'b10001;
                    default: glyph_row = 5'b00000;
                endcase
            end
            8'h49: begin
                case (row)
                    3'd0: glyph_row = 5'b11111;
                    3'd1: glyph_row = 5'b00100;
                    3'd2: glyph_row = 5'b00100;
                    3'd3: glyph_row = 5'b00100;
                    3'd4: glyph_row = 5'b00100;
                    3'd5: glyph_row = 5'b00100;
                    3'd6: glyph_row = 5'b11111;
                    default: glyph_row = 5'b00000;
                endcase
            end
            8'h4C: begin
                case (row)
                    3'd0: glyph_row = 5'b10000;
                    3'd1: glyph_row = 5'b10000;
                    3'd2: glyph_row = 5'b10000;
                    3'd3: glyph_row = 5'b10000;
                    3'd4: glyph_row = 5'b10000;
                    3'd5: glyph_row = 5'b10000;
                    3'd6: glyph_row = 5'b11111;
                    default: glyph_row = 5'b00000;
                endcase
            end
            8'h4D: begin
                case (row)
                    3'd0: glyph_row = 5'b10001;
                    3'd1: glyph_row = 5'b11011;
                    3'd2: glyph_row = 5'b10101;
                    3'd3: glyph_row = 5'b10101;
                    3'd4: glyph_row = 5'b10001;
                    3'd5: glyph_row = 5'b10001;
                    3'd6: glyph_row = 5'b10001;
                    default: glyph_row = 5'b00000;
                endcase
            end
            8'h4E: begin
                case (row)
                    3'd0: glyph_row = 5'b10001;
                    3'd1: glyph_row = 5'b11001;
                    3'd2: glyph_row = 5'b10101;
                    3'd3: glyph_row = 5'b10011;
                    3'd4: glyph_row = 5'b10001;
                    3'd5: glyph_row = 5'b10001;
                    3'd6: glyph_row = 5'b10001;
                    default: glyph_row = 5'b00000;
                endcase
            end
            8'h4F: begin
                case (row)
                    3'd0: glyph_row = 5'b01110;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b10001;
                    3'd3: glyph_row = 5'b10001;
                    3'd4: glyph_row = 5'b10001;
                    3'd5: glyph_row = 5'b10001;
                    3'd6: glyph_row = 5'b01110;
                    default: glyph_row = 5'b00000;
                endcase
            end
            8'h52: begin
                case (row)
                    3'd0: glyph_row = 5'b11110;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b10001;
                    3'd3: glyph_row = 5'b11110;
                    3'd4: glyph_row = 5'b10100;
                    3'd5: glyph_row = 5'b10010;
                    3'd6: glyph_row = 5'b10001;
                    default: glyph_row = 5'b00000;
                endcase
            end
            8'h53: begin
                case (row)
                    3'd0: glyph_row = 5'b01111;
                    3'd1: glyph_row = 5'b10000;
                    3'd2: glyph_row = 5'b10000;
                    3'd3: glyph_row = 5'b01110;
                    3'd4: glyph_row = 5'b00001;
                    3'd5: glyph_row = 5'b00001;
                    3'd6: glyph_row = 5'b11110;
                    default: glyph_row = 5'b00000;
                endcase
            end
            8'h54: begin
                case (row)
                    3'd0: glyph_row = 5'b11111;
                    3'd1: glyph_row = 5'b00100;
                    3'd2: glyph_row = 5'b00100;
                    3'd3: glyph_row = 5'b00100;
                    3'd4: glyph_row = 5'b00100;
                    3'd5: glyph_row = 5'b00100;
                    3'd6: glyph_row = 5'b00100;
                    default: glyph_row = 5'b00000;
                endcase
            end
            8'h55: begin
                case (row)
                    3'd0: glyph_row = 5'b10001;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b10001;
                    3'd3: glyph_row = 5'b10001;
                    3'd4: glyph_row = 5'b10001;
                    3'd5: glyph_row = 5'b10001;
                    3'd6: glyph_row = 5'b01110;
                    default: glyph_row = 5'b00000;
                endcase
            end
            8'h57: begin
                case (row)
                    3'd0: glyph_row = 5'b10001;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b10001;
                    3'd3: glyph_row = 5'b10101;
                    3'd4: glyph_row = 5'b10101;
                    3'd5: glyph_row = 5'b11011;
                    3'd6: glyph_row = 5'b10001;
                    default: glyph_row = 5'b00000;
                endcase
            end
            8'h3A: begin
                case (row)
                    3'd0: glyph_row = 5'b00000;
                    3'd1: glyph_row = 5'b00100;
                    3'd2: glyph_row = 5'b00100;
                    3'd3: glyph_row = 5'b00000;
                    3'd4: glyph_row = 5'b00100;
                    3'd5: glyph_row = 5'b00100;
                    default: glyph_row = 5'b00000;
                endcase
            end
            default: glyph_row = 5'b00000;
        endcase
    end
endfunction

function glyph_pixel;
    input [4:0] row_bits;
    input [2:0] col;
    begin
        case (col)
            3'd0: glyph_pixel = row_bits[4];
            3'd1: glyph_pixel = row_bits[3];
            3'd2: glyph_pixel = row_bits[2];
            3'd3: glyph_pixel = row_bits[1];
            3'd4: glyph_pixel = row_bits[0];
            default: glyph_pixel = 1'b0;
        endcase
    end
endfunction

function [7:0] brightness_channel;
    input [7:0] channel;
    input [1:0] level;
    reg signed [4:0] offset;
    reg signed [4:0] high_sum;
    begin
        case (level)
            2'd1: offset = 5'sd1;
            2'd2: offset = 5'sd2;
            2'd3: offset = -5'sd1;
            default: offset = 5'sd0;
        endcase
        high_sum = $signed({2'b00, channel[7:5]}) + offset;
        if (high_sum[4])
            brightness_channel = 8'd0;
        else if (high_sum[3])
            brightness_channel = 8'hFF;
        else
            brightness_channel = {high_sum[2:0], channel[4:0]};
    end
endfunction

function [7:0] contrast_channel;
    input [7:0] channel;
    input [1:0] level;
    reg [8:0] sum;
    reg [1:0] middle;
    begin
        sum = {1'b0, channel} + {2'b00, channel[7:1]} + {8'd0, (!channel[7] & channel[0])};
        middle = sum[7:6] - 2'd1;
        case (level)
            2'd1: begin
                if (sum[8:6] == 3'b000)
                    contrast_channel = 8'd0;
                else if (sum[8] && (sum[7] || sum[6]))
                    contrast_channel = 8'hFF;
                else
                    contrast_channel = {middle, sum[5:0]};
            end
            2'd2: begin
                if (channel[7:6] == 2'b00)
                    contrast_channel = 8'd0;
                else if (channel[7:6] == 2'b11)
                    contrast_channel = 8'hFF;
                else
                    contrast_channel = {channel[7], channel[5:0], 1'b0};
            end
            2'd3: begin
                contrast_channel = {channel[7], ~channel[7], channel[6:1]};
            end
            default: contrast_channel = channel;
        endcase
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

reg [10:0] x_cnt;
reg [9:0]  y_cnt;
reg        de_d;
reg        vs_d;
reg [3:0]  state_code_meta;
reg [3:0]  state_code_sync;
reg        auto_play_meta;
reg        auto_play_sync;
reg [1:0]  brightness_level_meta;
reg [1:0]  brightness_level_sync;
reg [1:0]  contrast_level_meta;
reg [1:0]  contrast_level_sync;
reg        param_default_meta;
reg        param_default_sync;
reg        transition_active_meta;
reg        transition_active_sync;
reg [9:0]  transition_reveal_x_meta;
reg [9:0]  transition_reveal_x_sync;
reg [2:0]  fade_level_meta;
reg [2:0]  fade_level_sync;

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        x_cnt <= 11'd0;
        y_cnt <= 10'd0;
        de_d <= 1'b0;
        vs_d <= 1'b0;
    end
    else begin
        de_d <= I_de;
        vs_d <= I_vs;

        if (vs_d != I_vs) begin
            x_cnt <= 11'd0;
            y_cnt <= 10'd0;
        end
        else if (I_de) begin
            if (!de_d)
                x_cnt <= 11'd0;
            else
                x_cnt <= x_cnt + 11'd1;
        end
        else begin
            x_cnt <= 11'd0;
            if (de_d)
                y_cnt <= y_cnt + 10'd1;
        end
    end
end

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        state_code_meta <= 4'd0;
        state_code_sync <= 4'd0;
        auto_play_meta <= 1'b0;
        auto_play_sync <= 1'b0;
        brightness_level_meta <= 2'd0;
        brightness_level_sync <= 2'd0;
        contrast_level_meta <= 2'd0;
        contrast_level_sync <= 2'd0;
        param_default_meta <= 1'b0;
        param_default_sync <= 1'b0;
        transition_active_meta <= 1'b0;
        transition_active_sync <= 1'b0;
        transition_reveal_x_meta <= 10'd640;
        transition_reveal_x_sync <= 10'd640;
        fade_level_meta <= 3'd0;
        fade_level_sync <= 3'd0;
    end
    else begin
        state_code_meta <= I_state_code;
        state_code_sync <= state_code_meta;
        auto_play_meta <= I_auto_play_en;
        auto_play_sync <= auto_play_meta;
        brightness_level_meta <= I_brightness_level;
        brightness_level_sync <= brightness_level_meta;
        contrast_level_meta <= I_contrast_level;
        contrast_level_sync <= contrast_level_meta;
        param_default_meta <= I_param_default_en;
        param_default_sync <= param_default_meta;
        transition_active_meta <= I_transition_active;
        transition_active_sync <= transition_active_meta;
        transition_reveal_x_meta <= I_transition_reveal_x;
        transition_reveal_x_sync <= transition_reveal_x_meta;
        fade_level_meta <= I_fade_level;
        fade_level_sync <= fade_level_meta;
    end
end

wire panel_area = I_enable && I_de && (x_cnt >= 11'd12) && (x_cnt < 11'd190) && (y_cnt >= 10'd12) && (y_cnt < 10'd142);
wire border_area = panel_area && ((x_cnt < 11'd14) || (x_cnt >= 11'd188) || (y_cnt < 10'd14) || (y_cnt >= 10'd140));

wire line0_area = I_enable && I_de && (x_cnt >= 11'd24) && (x_cnt < 11'd168) && (y_cnt >= 10'd22) && (y_cnt < 10'd38);
wire line1_area = I_enable && I_de && (x_cnt >= 11'd24) && (x_cnt < 11'd88) && (y_cnt >= 10'd46) && (y_cnt < 10'd62);
wire line2_area = I_enable && I_de && (x_cnt >= 11'd24) && (x_cnt < 11'd152) && (y_cnt >= 10'd70) && (y_cnt < 10'd86);
wire line3_area = I_enable && I_de && (x_cnt >= 11'd24) && (x_cnt < 11'd104) && (y_cnt >= 10'd94) && (y_cnt < 10'd110);
wire line4_area = I_enable && I_de && (x_cnt >= 11'd24) && (x_cnt < 11'd104) && (y_cnt >= 10'd118) && (y_cnt < 10'd134);

wire [10:0] line0_rel_x = x_cnt - 11'd24;
wire [9:0]  line0_rel_y = y_cnt - 10'd22;
wire [10:0] line1_rel_x = x_cnt - 11'd24;
wire [9:0]  line1_rel_y = y_cnt - 10'd46;
wire [10:0] line2_rel_x = x_cnt - 11'd24;
wire [9:0]  line2_rel_y = y_cnt - 10'd70;
wire [10:0] line3_rel_x = x_cnt - 11'd24;
wire [9:0]  line3_rel_y = y_cnt - 10'd94;
wire [10:0] line4_rel_x = x_cnt - 11'd24;
wire [9:0]  line4_rel_y = y_cnt - 10'd118;

wire [3:0] line0_index = line0_rel_x[7:4];
wire [2:0] line0_col = line0_rel_x[3:1];
wire [2:0] line0_row = line0_rel_y[3:1];
wire [3:0] line1_index = line1_rel_x[7:4];
wire [2:0] line1_col = line1_rel_x[3:1];
wire [2:0] line1_row = line1_rel_y[3:1];
wire [3:0] line2_index = line2_rel_x[7:4];
wire [2:0] line2_col = line2_rel_x[3:1];
wire [2:0] line2_row = line2_rel_y[3:1];
wire [3:0] line3_index = line3_rel_x[7:4];
wire [2:0] line3_col = line3_rel_x[3:1];
wire [2:0] line3_row = line3_rel_y[3:1];
wire [3:0] line4_index = line4_rel_x[7:4];
wire [2:0] line4_col = line4_rel_x[3:1];
wire [2:0] line4_row = line4_rel_y[3:1];

wire [7:0] line0_code = line0_char(line0_index);
wire [7:0] line1_code = line1_char(line1_index, state_code_sync);
wire [7:0] line2_code = line2_char(line2_index, auto_play_sync);
wire [1:0] brightness_level_effective = param_default_sync ? 2'd0 : brightness_level_sync;
wire [1:0] contrast_level_effective = param_default_sync ? 2'd0 : contrast_level_sync;
wire [7:0] line3_code = line3_char(line3_index, brightness_level_effective);
wire [7:0] line4_code = line4_char(line4_index, contrast_level_effective);
wire line0_pixel = line0_area && glyph_pixel(glyph_row(line0_code, line0_row), line0_col);
wire line1_pixel = line1_area && glyph_pixel(glyph_row(line1_code, line1_row), line1_col);
wire line2_pixel = line2_area && glyph_pixel(glyph_row(line2_code, line2_row), line2_col);
wire line3_pixel = line3_area && glyph_pixel(glyph_row(line3_code, line3_row), line3_col);
wire line4_pixel = line4_area && glyph_pixel(glyph_row(line4_code, line4_row), line4_col);
wire panel_text_pixel = line0_pixel || line1_pixel || line2_pixel || line3_pixel || line4_pixel;

wire [23:0] brightness_rgb = {brightness_channel(I_rgb[23:16], brightness_level_effective), brightness_channel(I_rgb[15:8], brightness_level_effective), brightness_channel(I_rgb[7:0], brightness_level_effective)};
wire [23:0] adjusted_rgb = {contrast_channel(brightness_rgb[23:16], contrast_level_effective), contrast_channel(brightness_rgb[15:8], contrast_level_effective), contrast_channel(brightness_rgb[7:0], contrast_level_effective)};
wire [10:0] transition_reveal_x_11 = {1'b0, transition_reveal_x_sync};
wire [10:0] transition_edge1_x = transition_reveal_x_11 + 11'd8;
wire [10:0] transition_edge2_x = transition_reveal_x_11 + 11'd16;
wire [10:0] transition_edge3_x = transition_reveal_x_11 + 11'd24;
wire [10:0] transition_edge4_x = transition_reveal_x_11 + {5'd0, TRANSITION_SOFT_WIDTH};
wire transition_edge0_area = transition_active_sync && I_enable && I_de && (x_cnt >= transition_reveal_x_11) && (x_cnt < transition_edge1_x);
wire transition_edge1_area = transition_active_sync && I_enable && I_de && (x_cnt >= transition_edge1_x) && (x_cnt < transition_edge2_x);
wire transition_edge2_area = transition_active_sync && I_enable && I_de && (x_cnt >= transition_edge2_x) && (x_cnt < transition_edge3_x);
wire transition_edge3_area = transition_active_sync && I_enable && I_de && (x_cnt >= transition_edge3_x) && (x_cnt < transition_edge4_x);
wire transition_mask_area = transition_active_sync && I_enable && I_de && (x_cnt >= transition_edge4_x);
wire [23:0] transition_rgb = transition_mask_area ? TRANSITION_MASK_COLOR :
                           transition_edge3_area ? TRANSITION_EDGE3_COLOR :
                           transition_edge2_area ? TRANSITION_EDGE2_COLOR :
                           transition_edge1_area ? TRANSITION_EDGE1_COLOR :
                           transition_edge0_area ? TRANSITION_EDGE0_COLOR :
                           adjusted_rgb;

wire [23:0] osd_rgb = panel_text_pixel ? TEXT_COLOR :
                     border_area ? BORDER_COLOR :
                     panel_area ? PANEL_COLOR :
                     transition_rgb;
wire [23:0] fade_rgb = {fade_channel(osd_rgb[23:16], fade_level_sync), fade_channel(osd_rgb[15:8], fade_level_sync), fade_channel(osd_rgb[7:0], fade_level_sync)};

assign O_rgb = fade_rgb;

endmodule
