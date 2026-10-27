module waveform_render (
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_vs,
    input  wire        I_de,
    input  wire [9:0]  I_x,
    input  wire [9:0]  I_y,
    input  wire [23:0] I_rgb,
    output wire        O_vs,
    output wire        O_de,
    output wire [23:0] O_rgb,
    output wire        O_wave_rd_en,
    output wire [9:0]  O_wave_rd_addr,
    input  wire [7:0]  I_wave_rd_data,
    input  wire        I_wave_rd_valid
);

    reg [23:0] rgb_d;
    reg [9:0] x_d;
    reg [9:0] y_d;
    reg vs_d;
    reg de_d;
    reg render_tag_d;

    function [1:0] modulo3;
        input [9:0] value;
        reg [4:0] weighted_sum;
        begin
            weighted_sum = value[0] + value[2] + value[4] + value[6] + value[8] +
                           ({4'd0,value[1]} << 1) + ({4'd0,value[3]} << 1) +
                           ({4'd0,value[5]} << 1) + ({4'd0,value[7]} << 1) +
                           ({4'd0,value[9]} << 1);
            case (weighted_sum)
                5'd0,5'd3,5'd6,5'd9,5'd12,5'd15: modulo3 = 2'd0;
                5'd1,5'd4,5'd7,5'd10,5'd13: modulo3 = 2'd1;
                default: modulo3 = 2'd2;
            endcase
        end
    endfunction

    function [7:0] blend_bar_channel;
        input [7:0] video_channel;
        input [7:0] bar_channel;
        reg [12:0] sum;
        begin
            sum = ({5'd0, bar_channel} << 3) +
                  ({5'd0, bar_channel} << 2) +
                  ({5'd0, video_channel} << 2) + 13'd8;
            blend_bar_channel = sum[11:4];
        end
    endfunction

    wire render_issue = I_de && (I_x < 10'd640) &&
                        (I_y >= 10'd400) && (I_y < 10'd472);

    // V3: 每 3 个像素对应一列（2px 条 + 1px 缝），共 213 列
    reg [1:0]  col_phase;
    reg [9:0]  col_idx;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            col_phase <= 2'd0;
            col_idx   <= 10'd0;
        end else if (!I_de) begin
            col_phase <= 2'd0;
            col_idx   <= 10'd0;
        end else if (!de_d) begin
            col_phase <= 2'd1;
            col_idx   <= 10'd1;
        end else if (col_phase == 2'd2) begin
            col_phase <= 2'd0;
            col_idx   <= col_idx + 10'd1;
        end else begin
            col_phase <= col_phase + 2'd1;
        end
    end

    assign O_wave_rd_en = render_issue;
    assign O_wave_rd_addr = col_idx;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            rgb_d <= 24'd0;
            x_d <= 10'd0;
            y_d <= 10'd0;
            vs_d <= 1'b0;
            de_d <= 1'b0;
            render_tag_d <= 1'b0;
        end else begin
            rgb_d <= I_rgb;
            x_d <= I_x;
            y_d <= I_y;
            vs_d <= I_vs;
            de_d <= I_de;
            render_tag_d <= render_issue;
        end
    end

    wire render_valid = render_tag_d && I_wave_rd_valid;
    // V3: 高度直接线性映射（数据 0~255 -> 0~63 像素）
    wire [5:0]  bar_height = I_wave_rd_data >> 2;
    wire [9:0]  bar_base   = 10'd471;                       // 基线
    wire        bar_column = (col_phase != 2'd2);

    // 纵向渐变（底部近白粉 -> 顶部深洋红）
    wire [9:0]  h_above = bar_base - y_d;
    wire [23:0] grad_rgb = (h_above < 10'd12) ? 24'hFFC2E0 :
                           (h_above < 10'd28) ? 24'hFF6FAD :
                           (h_above < 10'd46) ? 24'hE0357F :
                                                24'h9B2360;

    // 条：基线以上 bar_height 像素
    wire bar_pixel = render_valid && bar_column
                  && (y_d >= (bar_base - {4'd0, bar_height})) && (y_d < bar_base);
    // 基线：1px 亮粉
    wire base_pixel = render_valid && (y_d == bar_base);

    // 条色 75% 不透明叠加（保留一点画面氛围），基线用亮粉
    wire [23:0] bar_rgb = base_pixel ? 24'hFFB3D9 : grad_rgb;

    assign O_vs = vs_d;
    assign O_de = de_d;
    assign O_rgb = (bar_pixel || base_pixel) ? bar_rgb : rgb_d;

endmodule
