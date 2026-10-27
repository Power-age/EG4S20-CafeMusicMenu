`timescale 1ns/1ps
// 曲目倒计时回归（总长由 SD 域送 MM:SS）：
//   1) 总长 5:07 -> 剩余 5:07
//   2) 播 60 帧 -> 5:06，再 120 帧 -> 5:04
//   3) 切到 1:16 -> 剩余 1:16
//   4) playing=0 -> active=0（显示 --:--）
module tb_track_countdown;
    reg clk = 1'b0, rst = 1'b1, vs = 1'b0;
    reg [3:0] track_idx = 4'd0;
    reg [6:0] dur_min = 7'd5;
    reg [5:0] dur_sec = 6'd7;
    reg       playing = 1'b1;

    wire       active;
    wire [6:0] rem_min;
    wire [5:0] rem_sec;

    integer errs = 0;

    track_countdown u_dut (
        .clk(clk), .rst(rst), .vs(vs), .track_idx(track_idx),
        .dur_min(dur_min), .dur_sec(dur_sec), .playing(playing),
        .active(active), .rem_min(rem_min), .rem_sec(rem_sec)
    );

    always #19.861 clk = ~clk;

    task pulse_vs(input integer n);
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) begin
                @(negedge clk) vs = 1'b1;
                @(negedge clk) vs = 1'b0;
            end
        end
    endtask

    task expect_rem(input [6:0] em, input [5:0] es, input [8*20-1:0] tag);
        begin
            if (rem_min !== em || rem_sec !== es) begin
                errs = errs + 1;
                $display("ERR %0s: got %0d:%02d want %0d:%02d", tag, rem_min, rem_sec, em, es);
            end else begin
                $display("  OK %0s: %0d:%02d", tag, rem_min, rem_sec);
            end
        end
    endtask

    initial begin
        #500000;
        $display("TIMEOUT errs=%0d", errs);
        $finish;
    end

    initial begin
        repeat (6) @(posedge clk);
        rst <= 1'b0;
        repeat (6) @(posedge clk);
        expect_rem(7'd5, 6'd7, "dur 5:07");

        pulse_vs(60);
        repeat (4) @(posedge clk);
        expect_rem(7'd5, 6'd6, "after 60 frames");

        pulse_vs(120);
        repeat (4) @(posedge clk);
        expect_rem(7'd5, 6'd4, "after 180 frames");

        dur_min <= 7'd1;
        dur_sec <= 6'd16;
        repeat (6) @(posedge clk);
        expect_rem(7'd1, 6'd16, "switch to 1:16");

        playing <= 1'b0;
        repeat (4) @(posedge clk);
        if (active !== 1'b0) begin errs = errs + 1; $display("ERR active should be 0"); end
        else $display("  OK active=0 (--:--)");

        if (errs == 0) $display("COUNTDOWN_PASS");
        else           $display("COUNTDOWN_FAIL errs=%0d", errs);
        $finish;
    end
endmodule
