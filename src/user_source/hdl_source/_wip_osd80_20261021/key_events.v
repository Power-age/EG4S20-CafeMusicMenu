// 按键事件预处理：在现有 key_longshort（去抖 + 短按/长按）之上，
// 增加"双击判定"与"延迟单击"，供设置界面状态机直接消费。
//
// 事件语义：
//   short_pulse    —— 短按立即输出（面板关闭时用于切图/切歌）
//   long_pulse     —— 长按（600ms）输出
//   single_pulse   —— 延迟单击：松手后若 DOUBLE_MS 内无第二次按下才输出
//   double_pulse   —— 双击：第二次短按发生时立即输出，同时取消该次单击
//
// 说明：为避免"单击已输出后第二次按下才到"的竞态，single_pulse 的延迟
// 取与双击窗口相同的 DOUBLE_MS（默认 300ms）。规格文档写的 250ms 是下限，
// 这里取 300ms 保证不会既出单击又出双击。
module key_events #(
    parameter integer CLOCK_MHZ    = 25,
    parameter integer DEBOUNCE_MS  = 20,
    parameter integer LONG_MS      = 600,
    parameter integer DOUBLE_MS    = 300
)(
    input  wire clk,
    input  wire rst_n,
    input  wire button_in,       // 原始按键，低有效
    output wire short_pulse,
    output wire long_pulse,
    output reg  single_pulse,
    output reg  double_pulse
);

    localparam integer LONG_CYCLES   = LONG_MS   * CLOCK_MHZ * 1000;
    localparam integer DOUBLE_CYCLES = DOUBLE_MS * CLOCK_MHZ * 1000;

    // 复用既有去抖与长短按逻辑，避免重复面积
    key_longshort #(
        .CLOCK_MHZ     (CLOCK_MHZ),
        .DEBOUNCE_MS   (DEBOUNCE_MS),
        .LONG_CYCLES   (LONG_CYCLES),
        .REPEAT_CYCLES (LONG_CYCLES / 5),
        .REPEAT_ENABLE (0)
    ) u_kl (
        .clk         (clk),
        .rst_n       (rst_n),
        .button_in   (button_in),
        .short_pulse (short_pulse),
        .long_repeat (long_pulse),
        .long_active ()
    );

    // 自由计数器 + 时间戳比较：避免"倒计时到 0 才判断"的边界歧义
    localparam integer CNT_W = 24;

    reg [CNT_W-1:0] tmr;        // 自由运行
    reg [CNT_W-1:0] last_rel;   // 上次短按时刻
    reg             pend;       // 有一次待确认的单击
    reg             sp_d;       // short_pulse 打一拍，用于取上升沿
    wire            sp_rise = short_pulse & ~sp_d;
    wire [CNT_W-1:0] age = tmr - last_rel;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            single_pulse <= 1'b0;
            double_pulse <= 1'b0;
            tmr          <= {CNT_W{1'b0}};
            last_rel     <= {CNT_W{1'b0}};
            pend         <= 1'b0;
            sp_d         <= 1'b0;
        end else begin
            single_pulse <= 1'b0;
            double_pulse <= 1'b0;
            tmr          <= tmr + 1'b1;
            sp_d         <= short_pulse;

            if (sp_rise) begin
                if (pend && (age < DOUBLE_CYCLES[CNT_W-1:0])) begin
                    double_pulse <= 1'b1;   // 窗口内第二次短按 => 双击
                    pend         <= 1'b0;
                end else begin
                    pend     <= 1'b1;       // 记录一次待确认单击
                    last_rel <= tmr;
                end
            end else if (pend && (age >= DOUBLE_CYCLES[CNT_W-1:0])) begin
                single_pulse <= 1'b1;       // 窗口到期且无第二次按 => 单击
                pend         <= 1'b0;
            end
        end
    end

endmodule