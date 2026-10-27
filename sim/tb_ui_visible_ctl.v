`timescale 1ns/1ps
module tb_ui_visible_ctl;

    reg         clk;
    reg         rst;
    reg         vs;
    reg  [87:0] track_name;
    reg  [3:0]  vol_level;
    reg  [1:0]  img_idx;
    reg         auto_en;
    reg  [1:0]  brightness_level;
    reg  [1:0]  contrast_level;
    reg  [3:0]  state_code;
    wire [2:0]  ui_alpha;

    integer errors;
    integer f;

    ui_visible_ctl u_dut (
        .clk              (clk),
        .rst              (rst),
        .vs               (vs),
        .track_name       (track_name),
        .vol_level        (vol_level),
        .img_idx          (img_idx),
        .auto_en          (auto_en),
        .brightness_level (brightness_level),
        .contrast_level   (contrast_level),
        .state_code       (state_code),
        .ui_alpha         (ui_alpha)
    );

    initial clk = 1'b0;
    always #20 clk = ~clk;

    task vs_frame;
        begin
            @(negedge clk);
            vs = 1'b1;
            repeat (2) @(posedge clk);
            @(negedge clk);
            vs = 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    task check_alpha;
        input integer fid;
        input [2:0] exp;
        begin
            if (ui_alpha !== exp) begin
                errors = errors + 1;
                $display("MISMATCH after frame %0d got=%0d exp=%0d", fid, ui_alpha, exp);
            end
        end
    endtask

    task run_frames;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                vs_frame;
        end
    endtask

    task settle;
        begin
            track_name = 88'h00000000000000000000000A;
            vol_level  = 4'd1;
            img_idx    = 2'd0;
            auto_en    = 1'b0;
            brightness_level = 2'd0;
            contrast_level   = 2'd0;
            state_code = 4'd0;
            run_frames(3);
        end
    endtask

    task go_hidden;
        begin
            run_frames(301);
            run_frames(28);
        end
    endtask

    task wake_event;
        begin
            vs_frame;
            check_alpha(0, 3'd7);
            go_hidden;
            check_alpha(0, 3'd0);
        end
    endtask

    initial begin
        errors = 0;
        vs = 1'b0;
        track_name = 88'd0;
        vol_level = 4'd0; img_idx = 2'd0; auto_en = 1'b0;
        brightness_level = 2'd0; contrast_level = 2'd0; state_code = 4'd0;

        rst = 1'b1;
        repeat (6) @(posedge clk);
        @(negedge clk); rst = 1'b0;
        repeat (3) @(posedge clk);

        check_alpha(0, 3'd7);

        settle;
        run_frames(297);
        check_alpha(300, 3'd7);
        vs_frame;
        check_alpha(301, 3'd7);
        vs_frame;
        check_alpha(302, 3'd6);

        vs_frame; check_alpha(303, 3'd6);
        vs_frame; check_alpha(304, 3'd6);
        vs_frame; check_alpha(305, 3'd6);
        vs_frame; check_alpha(306, 3'd5);
        vs_frame; check_alpha(307, 3'd5);
        run_frames(2);
        vs_frame; check_alpha(310, 3'd4);
        run_frames(4); check_alpha(314, 3'd3);
        run_frames(4); check_alpha(318, 3'd2);
        run_frames(4); check_alpha(322, 3'd1);
        run_frames(4); check_alpha(326, 3'd0);
        vs_frame; check_alpha(327, 3'd0);
        run_frames(2); check_alpha(329, 3'd0);
        vs_frame; check_alpha(330, 3'd0);

        vol_level = 4'd2;
        vs_frame;
        check_alpha(331, 3'd7);

        run_frames(300);
        check_alpha(631, 3'd7);
        vs_frame;
        check_alpha(632, 3'd6);
        run_frames(3);
        check_alpha(635, 3'd6);
        vs_frame;
        check_alpha(636, 3'd5);
        img_idx = 2'd1;
        vs_frame;
        check_alpha(637, 3'd7);

        run_frames(300);
        check_alpha(937, 3'd7);
        run_frames(29);
        check_alpha(966, 3'd0);

        track_name = 88'h00000000000000000000000B;
        wake_event;

        img_idx = 2'd2;
        wake_event;

        auto_en = 1'b1;
        wake_event;

        brightness_level = 2'd2;
        wake_event;

        contrast_level = 2'd3;
        wake_event;

        state_code = 4'd5;
        repeat (3) @(posedge clk);
        wake_event;

        vs_frame;
        check_alpha(0, 3'd0);

        if (errors == 0)
            $display("PASS tb_ui_visible_ctl");
        else
            $display("FAIL tb_ui_visible_ctl errors=%0d", errors);
        $finish;
    end

endmodule
