// 曲目倒计时（视频域，轻量版）
//
// 曲目总长由 sd_card_bmp 在本域算好后送来（MM:SS，14 位），本模块只负责：
//   1. 用 vsync 帧计数累计"已播"（60 帧 = 1 秒），全程留在视频域，不跨域数样本；
//   2. 剩余 = 总长 - 已播，归零钳位。
// 切歌（曲目号变化、总长变化）或重新开始播放（playing 上升沿）都会把已播清零。
module track_countdown (
    input  wire        clk,
    input  wire        rst,
    input  wire        vs,
    input  wire [3:0]  track_idx,
    input  wire [6:0]  dur_min,       // 曲目总长（分），来自 SD 域
    input  wire [5:0]  dur_sec,       // 曲目总长（秒）
    input  wire        playing,
    input  wire        adj_pulse,     // 快进/快退一次（±10s）
    input  wire        adj_fwd,
    output wire        active,        // 有曲目在放
    output reg  [6:0]  rem_min,
    output reg  [5:0]  rem_sec
);

    reg [6:0]  el_min;
    reg [5:0]  el_sec;
    reg [5:0]  frame_cnt;
    reg        vs_d;
    reg        play_d;
    reg [3:0]  idx_q;
    reg [6:0]  dmin_q;
    reg [5:0]  dsec_q;

    wire vs_rise   = vs & ~vs_d;
    wire play_rise = playing & ~play_d;
    wire reload    = (track_idx != idx_q) || (dur_min != dmin_q) || (dur_sec != dsec_q) || play_rise;

    assign active = playing;

    // ---------------- 已播时间（帧计数） ----------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            vs_d      <= 1'b0;
            play_d    <= 1'b0;
            el_min    <= 7'd0;
            el_sec    <= 6'd0;
            frame_cnt <= 6'd0;
            idx_q     <= 4'd0;
            dmin_q    <= 7'd0;
            dsec_q    <= 6'd0;
        end else begin
            vs_d   <= vs;
            play_d <= playing;
            if (reload) begin
                el_min    <= 7'd0;
                el_sec    <= 6'd0;
                frame_cnt <= 6'd0;
                idx_q     <= track_idx;
                dmin_q    <= dur_min;
                dsec_q    <= dur_sec;
            end else if (adj_pulse) begin
                if (adj_fwd) begin
                    if (el_sec >= 6'd50) begin
                        el_sec <= el_sec - 6'd50;
                        el_min <= el_min + 7'd1;
                    end else el_sec <= el_sec + 6'd10;
                end else begin
                    if (el_sec >= 6'd10) el_sec <= el_sec - 6'd10;
                    else if (el_min != 7'd0) begin
                        el_sec <= el_sec + 6'd50;
                        el_min <= el_min - 7'd1;
                    end else el_sec <= 6'd0;
                end
            end else if (vs_rise && playing) begin
                if (frame_cnt >= 6'd59) begin
                    frame_cnt <= 6'd0;
                    if (el_sec >= 6'd59) begin
                        el_sec <= 6'd0;
                        if (el_min >= 7'd99) el_min <= 7'd99;
                        else                el_min <= el_min + 7'd1;
                    end else el_sec <= el_sec + 6'd1;
                end else frame_cnt <= frame_cnt + 6'd1;
            end
        end
    end

    // ---------------- 剩余 = 总长 - 已播 ----------------
    always @(*) begin
        if (!active || (dur_min == 7'd0 && dur_sec == 6'd0)) begin
            rem_min = 7'd0;
            rem_sec = 6'd0;
        end else if ({dur_min, dur_sec} > {el_min, el_sec}) begin
            if (dur_sec >= el_sec) begin
                rem_sec = dur_sec - el_sec;
                rem_min = dur_min - el_min;
            end else begin
                rem_sec = dur_sec + 6'd60 - el_sec;
                rem_min = dur_min - el_min - 7'd1;
            end
        end else begin
            rem_min = 7'd0;
            rem_sec = 6'd0;
        end
    end

endmodule
