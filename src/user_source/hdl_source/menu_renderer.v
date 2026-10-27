// 设置面板文字渲染器（V2-13：显示真实参数值）
//
// 布局：19 槽位 × 8 格，槽 0~14 为名称区、槽 15~18 为数值区（右对齐 4 字符）
// 行 0 = 标题 SETTINGS；行 1~7 = 七个设置项
//
// 重绘：由 redraw 脉冲触发（选中行变化 / 参数变化 / 面板打开）
module menu_renderer (
    input  wire       clk,
    input  wire       rst,
    input  wire       vis,
    input  wire       buf_ready,
    input  wire       redraw,
    input  wire [2:0] sel_row,
    input  wire       editing,      // 编辑态（闪烁区分）
    input  wire       blink,        // 闪烁相位
    // 七项参数（V2-13）
    input  wire [3:0] p_volume,
    input  wire [2:0] p_bright,
    input  wire [2:0] p_contrast,
    input  wire [2:0] p_trans,
    input  wire       p_auto,
    input  wire [3:0] p_period,
    input  wire       p_info,
    input  wire       p_tone,
    output wire       req_valid,
    output wire [6:0] req_ascii,
    output wire [7:0] req_x,
    output wire [6:0] req_y,
    output wire [1:0] req_type,
    output wire       req_fill,
    input  wire       req_ready,
    output wire       busy
);

    localparam [6:0] SP = 7'd32;

    reg [2:0] row;
    reg [4:0] idx;
    reg       drawn;
    reg       running;

    // ---------------- 名称区（槽 0~14） ----------------
    function [6:0] name_char;
        input [2:0] line_index;
        input [4:0] slot_index;
        reg [119:0] text_line;      // 15 字符 × 8 位
        reg [119:0] shifted;
        begin
            case (line_index)
                3'd0: text_line = "     SETTINGS  ";
                3'd1: text_line = "VOLUME         ";
                3'd2: text_line = "BRIGHT         ";
                3'd3: text_line = "CONTRAST       ";
                3'd4: text_line = "TRANS          ";
                3'd5: text_line = "AUTO           ";
                3'd6: text_line = "PERIOD         ";
                3'd7: text_line = "TONE           ";
                default: text_line = {15{8'h20}};   // 空白行（清残留）
            endcase
            shifted = text_line >> ((5'd14 - slot_index) * 8);
            name_char = shifted[6:0];
        end
    endfunction

    // ---------------- 数值区（槽 15~18，4 字符右对齐） ----------------
    function [6:0] val_char;
        input [2:0] line_index;
        input [4:0] i;              // 0=最左 ... 3=最右
        reg [3:0] tens;
        reg [3:0] ones;
        begin
            val_char = SP;
            case (line_index)
                // VOLUME 0~15：两位数字
                3'd1: begin
                    tens = (p_volume >= 4'd10) ? 4'd1 : 4'd0;
                    ones = (p_volume >= 4'd10) ? (p_volume - 4'd10) : p_volume;
                    case (i)
                        5'd2:    val_char = 7'd48 + {3'd0, tens};
                        5'd3:    val_char = 7'd48 + {3'd0, ones};
                        default: val_char = SP;
                    endcase
                end
                // BRIGHT 0~3
                3'd2: begin
                    val_char = (i == 5'd3) ? (7'd48 + {4'd0, p_bright}) : SP;
                end
                // CONTRAST 0~3
                3'd3: begin
                    val_char = (i == 5'd3) ? (7'd48 + {4'd0, p_contrast}) : SP;
                end
                // TRANS：0=FADE（淡出淡入）1=WIPE（揭幕）
                3'd4: begin
                    case (i)
                        5'd0: val_char = p_trans[0] ? "W" : "F";
                        5'd1: val_char = p_trans[0] ? "I" : "A";
                        5'd2: val_char = p_trans[0] ? "P" : "D";
                        5'd3: val_char = p_trans[0] ? "E" : "E";
                        default: val_char = SP;
                    endcase
                end
                // AUTO：ON / OFF
                3'd5: begin
                    case (i)
                        5'd1: val_char = p_auto ? SP : "O";
                        5'd2: val_char = p_auto ? "O" : "F";
                        5'd3: val_char = p_auto ? "N" : "F";
                        default: val_char = SP;
                    endcase
                end
                // PERIOD 1~10 秒
                3'd6: begin
                    tens = (p_period == 4'd10) ? 4'd1 : 4'd0;
                    ones = (p_period == 4'd10) ? 4'd0 : p_period;
                    case (i)
                        5'd1:    val_char = (p_period == 4'd10) ? "1" : SP;
                        5'd2:    val_char = 7'd48 + {3'd0, (p_period == 4'd10) ? 4'd0 : ones};
                        5'd3:    val_char = "S";
                        default: val_char = SP;
                    endcase
                end
                // TONE：ON / OFF
                3'd7: begin
                    case (i)
                        5'd1: val_char = p_tone ? SP : "O";
                        5'd2: val_char = p_tone ? "O" : "F";
                        5'd3: val_char = p_tone ? "N" : "F";
                        default: val_char = SP;
                    endcase
                end
                // 兜底
                default: val_char = SP;
            endcase
        end
    endfunction

    function [6:0] slot_char;
        input [2:0] line_index;
        input [4:0] slot_index;
        begin
            if (line_index == 3'd0 && slot_index >= 5'd15)
                slot_char = SP;
            else if (slot_index >= 5'd15)
                slot_char = val_char(line_index, slot_index - 5'd15);
            else
                slot_char = name_char(line_index, slot_index);
        end
    endfunction

    assign req_valid = running && vis;
    assign req_ascii = slot_char(row, idx);
    assign req_x     = {3'd0, idx};
    assign req_y     = {1'b0, row, 3'b000} + 7'd8;
    // 选中行高亮；编辑态时随 blink 相位交替熄灭/点亮，形成闪烁
    wire hl_row = (row != 3'd0) && (row == ({1'b0, sel_row} + 4'd1));
    wire hl_on  = hl_row && !(editing && blink);
    assign req_type  = hl_on ? 2'b11 : 2'b10;
    assign req_fill  = 1'b0;
    assign busy      = running;

    reg  redraw_pending;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            row            <= 3'd0;
            idx            <= 5'd0;
            drawn          <= 1'b0;
            running        <= 1'b0;
            redraw_pending <= 1'b0;
        end else if (!vis) begin
            drawn          <= 1'b0;
            running        <= 1'b0;
            redraw_pending <= 1'b0;
        end else if (running) begin
            // 2026/10/24：绘制进行中收到 redraw 只打标、不打断本轮，
            // 保证每一轮都完整覆盖 8 行（否则最后一行会停在半截）
            if (redraw) begin
                redraw_pending <= 1'b1;
            end else if (req_ready) begin
                if (idx == 5'd18) begin
                    idx <= 5'd0;
                    if (row == 3'd7) begin
                        running <= 1'b0;
                        drawn   <= 1'b1;
                    end else begin
                        row <= row + 3'd1;
                    end
                end else begin
                    idx <= idx + 5'd1;
                end
            end
        end else begin
            // 空闲态：有待重绘就先作废本轮结果，下一拍重新开画
            if (redraw || redraw_pending) begin
                drawn          <= 1'b0;
                redraw_pending <= 1'b0;
            end else if (buf_ready && !drawn) begin
                running <= 1'b1;
                row     <= 3'd0;
                idx     <= 5'd0;
            end
        end
    end

endmodule
