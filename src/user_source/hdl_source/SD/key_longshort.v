//============================================================================
// key_longshort.v
// 任务 18（阶段 A：数字音量调节）—— 短按 / 长按判别 + 长按自动重复
//   - 内部例化 ax_debounce 做消抖，输入为未消抖原始按键（板卡按键低有效：
//     空闲为高、按下为低，与 ax_debounce 复位 button_out=1 一致）。
//   - 短按（按住时长 < LONG_CYCLES 后松开）：松手产生 1 拍 short_pulse。
//   - 长按（按住达 LONG_CYCLES）：long_active 拉高，立刻产生 1 个 long_repeat；
//     REPEAT_ENABLE=1 时此后每 REPEAT_CYCLES 再产生 1 个，REPEAT_ENABLE=0 时
//     整个长按只产生这 1 个；进入长按后松手【不再】产生 short_pulse，避免误触发短按功能。
// 时钟默认 audio_mclk = 12.288MHz：
//   LONG_CYCLES  = 600ms *12.288M ~= 7373
//   REPEAT_CYCLES= 120ms *12.288M ~= 1475
//============================================================================
module key_longshort
#(
    parameter integer DEBOUNCE_MS    = 20,
    parameter integer CLOCK_MHZ      = 12,
    parameter integer LONG_CYCLES    = 7372800,
    parameter integer REPEAT_CYCLES  = 1474560,
    parameter integer REPEAT_ENABLE  = 1
)
(
    input  wire clk,          // 用 audio_mclk
    input  wire rst_n,        // 低有效复位
    input  wire button_in,    // 未消抖原始按键（低有效）
    output reg  short_pulse,  // 短按松手 1 拍脉冲
    output reg  long_repeat,  // 长按重复 1 拍脉冲
    output reg  long_active   // 长按状态电平
);

    wire key_lvl;   // 消抖后电平：1=空闲 0=按下

    ax_debounce
    #(
        .N(32),
        .FREQ(CLOCK_MHZ),
        .MAX_TIME(DEBOUNCE_MS)
    )
    u_debounce
    (
        .clk            (clk),
        .rst            (~rst_n),
        .button_in      (button_in),
        .button_posedge (),
        .button_negedge (),
        .button_out     (key_lvl)
    );

    localparam [1:0] S_IDLE   = 2'd0,
                     S_TIMING = 2'd1,
                     S_LONG   = 2'd2;

    reg [1:0]  state;
    reg [23:0] press_cnt;
    reg [23:0] rep_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            press_cnt   <= 24'd0;
            rep_cnt     <= 24'd0;
            long_active <= 1'b0;
            short_pulse <= 1'b0;
            long_repeat <= 1'b0;
        end else begin
            short_pulse <= 1'b0;
            long_repeat <= 1'b0;
            case (state)
                S_IDLE: begin
                    long_active <= 1'b0;
                    press_cnt   <= 24'd0;
                    rep_cnt     <= 24'd0;
                    if (key_lvl == 1'b0)       // 检测到按下
                        state <= S_TIMING;
                end

                S_TIMING: begin
                    if (key_lvl == 1'b1) begin  // 未达长按阈值即松开 -> 短按
                        short_pulse <= 1'b1;
                        state       <= S_IDLE;
                    end else if (press_cnt >= LONG_CYCLES - 1'b1) begin
                        // 达到长按阈值 -> 进入长按，立刻发第 1 个 repeat
                        state       <= S_LONG;
                        long_active <= 1'b1;
                        long_repeat <= 1'b1;
                        rep_cnt     <= 24'd0;
                        press_cnt   <= 24'd0;
                    end else begin
                        press_cnt <= press_cnt + 1'b1;
                    end
                end

                S_LONG: begin
                    if (key_lvl == 1'b1) begin  // 长按后松开：回空闲，不发 short
                        state       <= S_IDLE;
                        long_active <= 1'b0;
                    end else if (REPEAT_ENABLE != 0) begin
                        if (rep_cnt >= REPEAT_CYCLES - 1'b1) begin
                            long_repeat <= 1'b1;
                            rep_cnt     <= 24'd0;
                        end else begin
                            rep_cnt <= rep_cnt + 1'b1;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
