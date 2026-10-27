`timescale 1ns/1ps
//============================================================================
// tb_audio_volume.v
// 验证 audio_volume_gain：
//   1. 默认档 12：增益≈0.8（26208/32768），正/负输入缩放正确；
//   2. 连续 12 次减 -> 档 0，输出静音 0；
//   3. 连续 20 次加 -> 档 15（限幅），增益≈1.0；
//   4. 满档后再加，档位保持 15。
//============================================================================
module tb_audio_volume;

    reg clk = 0;
    reg rst_n;
    reg up = 0, dn = 0;
    reg signed [23:0] in_l, in_r;

    wire signed [23:0] out_l, out_r;
    wire [3:0] vol;

    integer ol, orr;
    integer errors = 0;

    always #41 clk = ~clk;

    audio_volume_gain
    #(.DEFAULT_VOL(4'd12))
    dut
    (
        .clk(clk), .rst_n(rst_n),
        .vol_up_pulse(up), .vol_down_pulse(dn),
        .external_vol_level(4'd0),
        .in_valid(1'b1),
        .in_left(in_l), .in_right(in_r),
        .out_left(out_l), .out_right(out_r),
        .vol_level(vol)
    );

    function integer iabs;
        input integer x;
        iabs = (x < 0) ? -x : x;
    endfunction

    task near;
        input integer a, e, t;
        begin
            if (iabs(a - e) > t) begin
                $display("  FAIL: got %0d expect ~%0d (tol %0d)", a, e, t);
                errors = errors + 1;
            end else begin
                $display("  ok: %0d ~ %0d", a, e);
            end
        end
    endtask

    task chkvol;
        input integer e;
        begin
            if (vol !== e[3:0]) begin
                $display("  FAIL: vol=%0d expect %0d", vol, e);
                errors = errors + 1;
            end else $display("  ok: vol=%0d", e);
        end
    endtask

    task do_up;
        begin
            @(negedge clk); up = 1;
            @(posedge clk);
            @(negedge clk); up = 0;
            repeat (3) @(posedge clk);
        end
    endtask

    task do_dn;
        begin
            @(negedge clk); dn = 1;
            @(posedge clk);
            @(negedge clk); dn = 0;
            repeat (3) @(posedge clk);
        end
    endtask

    integer i;

    initial begin
        in_l = 24'sd10000;
        in_r = -24'sd10000;
        rst_n = 0;
        repeat (200) @(posedge clk);
        rst_n = 1;
        repeat (100) @(posedge clk);

        // ---- 场景1：默认档 12，增益 26208/32768 ≈ 0.8 ----
        $display("[S1 default vol=12]");
        chkvol(12);
        ol = out_l; orr = out_r;
        // +10000*26208/32768 = 7998.05 -> 7998 ; 负数 floor -> -7999
        near(ol, 7998, 2);
        near(orr, -7999, 2);

        // ---- 场景2：连减 12 次 -> 0，静音 ----
        $display("[S2 down to 0]");
        for (i=0; i<12; i=i+1) do_dn;
        chkvol(0);
        ol = out_l; orr = out_r;
        if (ol !== 0 || orr !== 0) begin
            $display("  FAIL: mute out_l=%0d out_r=%0d", ol, orr); errors=errors+1;
        end else $display("  ok: muted (0)");

        // ---- 场景3：连加 20 次 -> 15（限幅） ----
        $display("[S3 up to 15]");
        for (i=0; i<20; i=i+1) do_up;
        chkvol(15);
        ol = out_l; orr = out_r;
        // +10000*32760/32768 = 9997.56 -> 9997 ; 负 -> -9998
        near(ol, 9997, 1);
        near(orr, -9998, 1);

        // ---- 场景4：满档再加，保持 15 ----
        $display("[S4 stay 15]");
        for (i=0; i<5; i=i+1) do_up;
        chkvol(15);

        if (errors == 0)
            $display("==== AUDIO_VOLUME TEST PASS ====");
        else
            $fatal(1, "AUDIO_VOLUME TEST FAIL (%0d)", errors);
        $finish;
    end

    initial begin
        #50_000_000;
        $fatal(1, "audio volume timeout");
    end

endmodule
