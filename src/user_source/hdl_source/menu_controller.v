// 设置界面交互状态机（V2-12）
//
// 按键语义（见 项目方案.md §4.0）：
//   KEY2 = 减（minus）、KEY4 = 加（plus）、KEY3 = 选中（sel）
//   面板关闭：减/加 短按切图、长按切歌；选中 短按开面板
//   面板打开（浏览）：减 = 高亮下移、加 = 高亮上移；选中 单击 = 进编辑、双击 = 关面板
//   面板打开（编辑）：减 = 值 -1、加 = 值 +1；选中 短按 = 确认回浏览
//   15 秒无操作自动关闭
//
// 说明：本模块只负责交互与参数寄存器；参数接入各模块由 V2-13 完成。
module menu_controller #(
    parameter integer CLOCK_MHZ   = 25,
    parameter integer TIMEOUT_MS  = 15000
)(
    input  wire       clk,
    input  wire       rst,
    // 来自 key_events 的事件（单拍脉冲）
    input  wire       minus_short,
    input  wire       minus_long,
    input  wire       plus_short,
    input  wire       plus_long,
    input  wire       sel_press,      // 已消抖的「选中」短按脉冲（复用 key3_trig）
    // 输出
    output reg        panel_vis,
    output reg  [2:0] sel_row,
    output reg        editing,
    output wire       active,     // 面板打开（用于屏蔽原按键功能）
    // 七项参数输出（V2-13）
    output wire [3:0] o_volume,
    output wire [2:0] o_bright,
    output wire [2:0] o_contrast,
    output wire [2:0] o_trans,
    output wire       o_auto,
    output wire [3:0] o_period,
    output wire       o_info,
output wire       o_tone,
    output reg        redraw,     // 参数或选中行变化时的一拍脉冲
    output reg        blink       // 编辑态闪烁相位
);

    localparam [1:0] S_CLOSED = 2'd0;
    localparam [1:0] S_BROWSE = 2'd1;
    localparam [1:0] S_EDIT   = 2'd2;

    localparam integer TIMEOUT_CYCLES = TIMEOUT_MS * CLOCK_MHZ * 1000;

    reg [1:0]  state;
    // 编辑态闪烁：约 400ms 翻转一次
    localparam integer BLINK_CYCLES = 400 * CLOCK_MHZ * 1000;
    reg [24:0] blink_cnt;
    reg        editing_q;
    wire       blink_tick = (blink_cnt >= BLINK_CYCLES[24:0] - 25'd1);
    reg [28:0] idle_cnt;
    reg        suppress_single;   // 开关面板的那一按，其延迟单击事件要忽略
reg  [1:0] redraw_hold;

    // ---- 单击/双击判别（复用已消抖的 sel_press，避免再例化一套去抖） ----
    localparam integer WIN_CYCLES = 300 * CLOCK_MHZ * 1000;   // 300ms
    localparam integer WIN_WIDTH = (WIN_CYCLES < 2) ? 1 : $clog2(WIN_CYCLES + 1);
    reg [WIN_WIDTH-1:0] window_count;
    reg        pend;

    reg sel_short;
    reg sel_single;
    reg sel_double;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            window_count <= {WIN_WIDTH{1'b0}};
            pend       <= 1'b0;
            sel_short  <= 1'b0;
            sel_single <= 1'b0;
            sel_double <= 1'b0;
        end else begin
            sel_short  <= 1'b0;
            sel_single <= 1'b0;
            sel_double <= 1'b0;
            if (sel_press) begin
                sel_short <= 1'b1;
                if (pend && (window_count < WIN_CYCLES)) begin
                    sel_double <= 1'b1;
                    pend       <= 1'b0;
                end else begin
                    pend       <= 1'b1;
                    window_count <= {{(WIN_WIDTH-1){1'b0}}, 1'b1};
                end
            end else if (pend && (window_count >= WIN_CYCLES)) begin
                sel_single <= 1'b1;
                pend       <= 1'b0;
            end else if (pend) begin
                window_count <= window_count + 1'b1;
            end
        end
    end

    assign active = (state != S_CLOSED) || sel_press || sel_short;


    wire any_event = minus_short | minus_long | plus_short | plus_long |
                     sel_short | sel_single | sel_double;

    // ---------------- 七项参数寄存器（V2-13 接入各模块） ----------------
    reg [3:0] p_volume;      // 0~15
    reg [2:0] p_bright;      // 0~4
    reg [2:0] p_contrast;    // 0~4
    reg [2:0] p_trans;       // 0~3：0=FADE 1=FLASH 2=SCAN 3=CUT
    reg       p_auto;        // 0/1
    reg [3:0] p_period;      // 1~10 秒
    reg       p_info;        // 0/1
reg       p_tone;        // 0/1

    assign o_volume   = p_volume;
    assign o_bright   = p_bright;
    assign o_contrast = p_contrast;
    assign o_trans    = p_trans;
    assign o_auto     = p_auto;
    assign o_period   = p_period;
    assign o_info     = p_info;
assign o_tone     = p_tone;

    // 参数或选中行任一变化 -> 触发面板重绘
    wire [22:0] param_now = {sel_row, p_volume, p_bright, p_contrast, p_trans, p_auto, p_period, p_info, p_tone};
    reg  [22:0] param_q;


    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= S_CLOSED;
            panel_vis  <= 1'b0;
            sel_row    <= 3'd0;
            editing    <= 1'b0;
            idle_cnt   <= 29'd0;
            suppress_single <= 1'b0;
            param_q    <= 23'd0;
            redraw     <= 1'b0;
    redraw_hold <= 2'd0;
            blink      <= 1'b0;
            blink_cnt  <= 25'd0;
            editing_q  <= 1'b0;
            p_volume   <= 4'd0;
            p_bright   <= 3'd4;   // 2026/10/24 用户要求：默认最亮（整体偏暗，可在菜单里下调）
            p_contrast <= 3'd2;   // 居中（正常对比度）
            p_trans    <= 3'd0;
            p_auto     <= 1'b0;   // V2-13: 默认 OFF（用户要求）
            p_period   <= 4'd3;
            p_info     <= 1'b1;
    p_tone     <= 1'b0;
        end else begin
            // 编辑态闪烁相位
            if (editing) begin
                if (blink_tick) begin
                    blink_cnt <= 25'd0;
                    blink     <= ~blink;
                end else begin
                    blink_cnt <= blink_cnt + 25'd1;
                end
            end else begin
                blink_cnt <= 25'd0;
                blink     <= 1'b0;
            end

            // 编辑态切换也要重绘（否则退出编辑时可能停在"熄灭相"）
            editing_q <= editing;

            // 参数变化 / 闪烁翻转 / 编辑态切换 -> 重绘
            if ((param_now != param_q) || blink_tick || (editing != editing_q)) begin
                param_q <= param_now;
                redraw  <= 1'b1;
                redraw_hold <= 2'd2;
            end else if (redraw_hold != 2'd0) begin
                redraw      <= 1'b1;
                redraw_hold <= redraw_hold - 2'd1;
            end else begin
                redraw  <= 1'b0;
            end

            // 空闲计时（任何事件清零）
            if (any_event)
                idle_cnt <= 29'd0;
            else if (idle_cnt != TIMEOUT_CYCLES)
                idle_cnt <= idle_cnt + 29'd1;

            case (state)
                S_CLOSED: begin
                    panel_vis <= 1'b0;
                    editing   <= 1'b0;
                    if (sel_short) begin
                        state           <= S_BROWSE;
                        panel_vis       <= 1'b1;
                        sel_row         <= 3'd0;
                        idle_cnt        <= 29'd0;
                        suppress_single <= 1'b1;   // 这一按的延迟单击不要进编辑
                    end
                end
                S_BROWSE: begin
                    panel_vis <= 1'b1;
                    editing   <= 1'b0;
                    if (sel_double) begin
                        state     <= S_CLOSED;
                        panel_vis <= 1'b0;
                    end else if (sel_single && !suppress_single) begin
                        state   <= S_EDIT;
                        editing <= 1'b1;
                    end else if (sel_short) begin
                        suppress_single <= 1'b0;
                    end else if (minus_short) begin
                        sel_row  <= (sel_row == 3'd6) ? 3'd0 : (sel_row + 3'd1);
                        idle_cnt <= 29'd0;
                    end else if (plus_short) begin
                        sel_row  <= (sel_row == 3'd0) ? 3'd6 : (sel_row - 3'd1);
                        idle_cnt <= 29'd0;
                end
                end
                S_EDIT: begin
                    panel_vis <= 1'b1;
                    editing   <= 1'b1;
                    if (sel_short || sel_double) begin
                        state   <= S_BROWSE;
                        editing <= 1'b0;
                        suppress_single <= 1'b1;
                        idle_cnt <= 29'd0;
                    end else if (minus_short) begin
                        idle_cnt <= 29'd0;
                        case (sel_row)
                            3'd0: p_volume   <= (p_volume   == 4'd0)  ? 4'd0  : (p_volume   - 4'd1);
                            3'd1: p_bright   <= (p_bright   == 3'd0)  ? 3'd0  : (p_bright   - 3'd1);
                            3'd2: p_contrast <= (p_contrast == 3'd0)  ? 3'd0  : (p_contrast - 3'd1);
                            3'd3: p_trans    <= (p_trans    == 3'd0)  ? 3'd0  : (p_trans    - 3'd1);
                            3'd4: p_auto     <= ~p_auto;
                            3'd5: p_period   <= (p_period   == 4'd1)  ? 4'd1  : (p_period   - 4'd1);
                            3'd6: p_tone     <= ~p_tone;
                            default: ;
                        endcase
                    end else if (plus_short) begin
                        idle_cnt <= 29'd0;
                        case (sel_row)
                            3'd0: p_volume   <= (p_volume   == 4'd15) ? 4'd15 : (p_volume   + 4'd1);
                            3'd1: p_bright   <= (p_bright   == 3'd4)  ? 3'd4  : (p_bright   + 3'd1);
                            3'd2: p_contrast <= (p_contrast == 3'd4)  ? 3'd4  : (p_contrast + 3'd1);
                            3'd3: p_trans    <= (p_trans    == 3'd1)  ? 3'd1  : (p_trans    + 3'd1);
                            3'd4: p_auto     <= ~p_auto;
                            3'd5: p_period   <= (p_period   == 4'd10) ? 4'd10 : (p_period   + 4'd1);
                            3'd6: p_tone     <= ~p_tone;
                            default: ;
                        endcase
                    end
                end
                default: state <= S_CLOSED;
            endcase
        end
    end

endmodule