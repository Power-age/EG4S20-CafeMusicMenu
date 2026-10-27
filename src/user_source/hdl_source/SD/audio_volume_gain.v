//============================================================================
// audio_volume_gain.v
// 任务 18（阶段 A）—— 数字音量：档位寄存器 + 对最终左右声道做有符号增益乘法
//   - 音量 16 档 vol[3:0]：0=静音、15=最大（增益≈1.0），上电默认 DEFAULT_VOL。
//   - vol_up_pulse / vol_down_pulse 为 1 拍增减脉冲（来自 key_longshort 的
//     short_pulse）；同时给增减则忽略；档位在 0 / 15 处限幅。
//   - 增益为组合乘法（DSP）：gain 用 Q15（1.0≈32768），满档取 32760（≈0.99976）
//     以保证系数为正、不削顶；输出 = (in * gain) >>> 15，截回 24bit signed。
//   - 增益为组合、不改变 valid（in_valid / 48kHz 节拍原样由顶层连 HDMI），
//     因此不引入采样对齐偏差。
//============================================================================
module audio_volume_gain
#(
    parameter [3:0] DEFAULT_VOL = 4'd0,
    parameter EXTERNAL_LEVEL = 0
)
(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               vol_up_pulse,
    input  wire               vol_down_pulse,
    input  wire [3:0]         external_vol_level,
    input  wire               in_valid,      // 仅用于层级清晰，本模块不改变 valid
    input  wire signed [23:0] in_left,
    input  wire signed [23:0] in_right,
    output wire signed [23:0] out_left,
    output wire signed [23:0] out_right,
    output wire [3:0]         vol_level
);

    wire [3:0] vol;

    generate
    if (EXTERNAL_LEVEL) begin : g_external
        assign vol = external_vol_level;
    end else begin : g_buttons
        reg [3:0] level;

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n)
                level <= DEFAULT_VOL;
            else case ({vol_up_pulse, vol_down_pulse})
                2'b10: level <= (level == 4'd15) ? 4'd15 : level + 4'd1;
                2'b01: level <= (level == 4'd0)  ? 4'd0  : level - 4'd1;
                default: level <= level;
            endcase
        end
        assign vol = level;
    end
    endgenerate

    assign vol_level = vol;

    // Q15 增益：16 档等 2 dB 步进，vol=15 -> 8775 (~0.2678, 约 -11.5 dB)，vol=0 -> 0
    reg [15:0] g16;
    always @(*) begin
        case (vol)
            4'd0 : g16 = 16'd0;
            4'd1 : g16 = 16'd349;
            4'd2 : g16 = 16'd440;
            4'd3 : g16 = 16'd554;
            4'd4 : g16 = 16'd697;
            4'd5 : g16 = 16'd878;
            4'd6 : g16 = 16'd1105;
            4'd7 : g16 = 16'd1391;
            4'd8 : g16 = 16'd1751;
            4'd9 : g16 = 16'd2204;
            4'd10: g16 = 16'd2775;
            4'd11: g16 = 16'd3493;
            4'd12: g16 = 16'd4398;
            4'd13: g16 = 16'd5537;
            4'd14: g16 = 16'd6970;
            default: g16 = 16'd8775;
        endcase
    end
    wire signed [15:0] gain_q15 = $signed(g16);

    wire signed [39:0] prod_l = in_left  * gain_q15;
    wire signed [39:0] prod_r = in_right * gain_q15;

    wire signed [24:0] scaled_l = prod_l >>> 15;
    wire signed [24:0] scaled_r = prod_r >>> 15;

    assign out_left  = scaled_l[23:0];
    assign out_right = scaled_r[23:0];

    // in_valid 不被使用（增益组合直通），显式避免悬空告警
    wire _unused = &{1'b0, in_valid};

endmodule
