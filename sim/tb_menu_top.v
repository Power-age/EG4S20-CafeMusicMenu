`timescale 1ns/1ps
module tb_menu_top;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1;
    reg minus_key = 0, plus_key = 0, select_key = 0;
    reg sw_con0 = 0, sw_key_mode = 0;
    reg signed [23:0] pcm_left = 24'sh7fffff, pcm_right = -24'sh800000;
    reg [23:0] rgb_in = 24'h204080;
    wire signed [23:0] pcm_out_left, pcm_out_right;
    wire [23:0] rgb_out;
    wire [3:0] actual_volume;
    wire vis, active, editing, redraw, valid, busy;
    wire [2:0] selected;
    wire [3:0] volume, period_value;
    wire [1:0] bright, contrast_value, old_bright, old_contrast;
    wire [2:0] trans;
    wire auto_value, info_value;
    wire [6:0] ascii, req_y;
    wire [7:0] req_x;
    wire [1:0] req_type;
    integer failures = 0, requests = 0, before_requests, i;
    integer b, c, sample_index;
    reg [6:0] chars [0:151];
    menu_top_extract dut (
        .video_clk(clk), .rst_all(rst), .k1_short_v(minus_key),
        .k2_short_v(plus_key), .key3_trig(select_key), .sw_con0(sw_con0),
        .sw_key_mode(sw_key_mode), .hdmi_audio_left(pcm_left),
        .hdmi_audio_right(pcm_right), .vol_audio_l(pcm_out_left),
        .vol_audio_r(pcm_out_right), .vol_level_a(actual_volume),
        .vout_data_wave(rgb_in), .vout_data_pre(rgb_out),
        .osd_clr_done(1'b1), .menu_req_ready(1'b1),
        .menu_panel_vis(vis), .menu_active(active), .menu_editing(editing),
        .menu_redraw(redraw), .menu_sel_row(selected), .m_volume(volume),
        .menu_req_fill(),
        .m_bright(bright), .m_contrast(contrast_value), .m_trans(trans),
        .m_auto(auto_value), .m_period(period_value), .m_info(info_value),
        .menu_req_valid(valid), .menu_busy(busy), .menu_req_ascii(ascii),
        .menu_req_y(req_y), .menu_req_x(req_x), .menu_req_type(req_type),
        .brightness_level(old_bright), .contrast_level(old_contrast)
    );
    always @(posedge clk) if (!rst && valid) begin
        requests = requests + 1;
        if (req_x < 19 && req_y >= 8 && req_y <= 64)
            chars[((req_y-8)/8)*19+req_x] = ascii;
    end
    task check;
        input condition;
        input [511:0] label_text;
        begin
            if (condition !== 1'b1) begin
                failures = failures + 1;
                $display("FAIL %0s", label_text);
            end
        end
    endtask
    task press;
        input integer which;
        begin
            @(negedge clk);
            minus_key = which == 0; plus_key = which == 1; select_key = which == 2;
            @(negedge clk); minus_key = 0; plus_key = 0; select_key = 0;
            repeat (5) @(negedge clk);
        end
    endtask
    task settle;
        begin repeat (180) @(negedge clk); end
    endtask
    task single_select;
        begin press(2); repeat (300010) @(negedge clk); end
    endtask
    initial begin
        repeat (3) @(negedge clk); rst = 0;
        repeat (8) @(negedge clk);
        check(actual_volume === 0 && pcm_out_left === 0 && pcm_out_right === 0, "reset mutes actual PCM");
        check(rgb_out === rgb_in, "reset preserves original RGB");
        press(2); settle;
        check(vis && active && selected == 0 && !editing, "open browse");
        check(old_bright == 0 && old_contrast == 0, "KEY3 must not change old image levels");
        check(volume === 0 && bright === 0 && contrast_value === 0 && trans === 0 && auto_value === 1 && period_value === 3 && info_value === 1, "all seven defaults match connected runtime levels");
        check(redraw !== 1'bz, "top redraw output connected");
        check(chars[17] == " " && chars[18] == " ", "title has no INFO value");
        before_requests = requests;
        press(0); settle;
        check(selected == 1, "KEY2 moves down");
        check(requests >= before_requests+152, "KEY2 redraw reaches renderer");
        for (i = 0; i < 6; i = i+1) begin press(0); settle; end
        check(selected == 0, "down wraps at final row");
        press(1); settle; check(selected == 6, "up wraps at first row");
        press(0); settle;
        repeat (300010) @(negedge clk);
        check(!editing, "opening press cannot enter edit later");
        single_select;
        check(editing, "single select enters edit");
        for (i = 0; i < 17; i = i+1) begin
            press(1); settle; check_pcm; 
        end
        check(volume == 15, "volume saturates at 15");
        check(chars[36] == "1" && chars[37] == "5", "volume 15 decimal display");
        for (i = 14; i >= 0; i = i-1) begin
            press(0); settle;
            check(volume == i, "volume decrement");
            check_pcm;
            check(chars[36] == (48+i/10) && chars[37] == (48+i%10), "all volume decimal digits");
        end
        press(0); settle; check(volume == 0, "volume saturates at zero");
        press(2);
        check(!editing, "confirm leaves edit");
        repeat (300010) @(negedge clk);
        check(!editing, "confirm delayed single must not reopen edit");
        press(0); settle; single_select;
        check(editing && selected == 1, "edit brightness");
        for (b = 1; b <= 3; b = b+1) begin
            press(1); settle;
            check(bright == b && old_bright == b, "brightness reaches actual video input");
        end
        press(1); settle; check(bright == 3, "brightness saturates high");
        for (b = 0; b < 4; b = b+1) begin press(0); settle; end
        check(bright == 0 && old_bright == 0, "brightness saturates low");
        for (b = 0; b < 4; b = b+1) begin
            press(2); repeat (300010) @(negedge clk);
            press(0); settle; single_select;
            check(editing && selected == 2, "edit contrast");
            for (c = 0; c < 4; c = c+1) begin
                check(contrast_value == c && old_contrast == c, "contrast reaches actual video input");
                for (sample_index = 0; sample_index < 256; sample_index = sample_index+1) begin
                    rgb_in = {sample_index[7:0], (8'd255-sample_index[7:0]), (sample_index[7:0]^8'h80)};
                    #1;
                    check(rgb_out === {channel_reference(rgb_in[23:16], b, c), channel_reference(rgb_in[15:8], b, c), channel_reference(rgb_in[7:0], b, c)}, "all RGB channels and clipping");
                end
                press(1); settle;
            end
            check(contrast_value == 3, "contrast saturates high");
            for (c = 0; c < 4; c = c+1) begin press(0); settle; end
            check(contrast_value == 0, "contrast saturates low");
            press(2); repeat (300010) @(negedge clk);
            press(1); settle; single_select;
            if (b < 3) begin press(1); settle; end
        end
        press(2); repeat (300010) @(negedge clk);
        sw_con0 = 1; sw_key_mode = 1;
        repeat (8) @(negedge clk);
        check(old_bright == 3 && old_contrast == 0 && actual_volume == 0, "legacy switches cannot alter menu-owned levels");
        press(2); repeat (10) @(negedge clk); press(2);
        check(!vis && !active, "double select closes panel");
        sw_key_mode = 0;
        press(1); settle; check(actual_volume == 0 && volume == 0, "closed menu short press cannot change gain");
        repeat (300010) @(negedge clk);
        press(2); settle;
        check(old_bright == 3 && old_contrast == 0 && bright == 3, "reopen preserves runtime settings");
        repeat (1300020) @(negedge clk);
        check(!vis && !active, "idle timeout closes panel");
        rst = 1; repeat (3) @(negedge clk); rst = 0;
        repeat (8) @(negedge clk);
        check(old_bright == 0 && old_contrast == 0 && actual_volume == 0 && volume == 0, "reset restores actual parameters");
        check(rgb_out === rgb_in && pcm_out_left === 0 && pcm_out_right === 0, "reset restores original image and silence");
        $display("RESULT top failures=%0d requests=%0d", failures, requests);
        if (failures) $fatal(1, "menu top integration mismatch");
        $display("PASS tb_menu_top"); $finish;
    end
    task check_pcm;
        reg signed [63:0] expected_left, expected_right;
        begin
            expected_left = $signed(pcm_left);
            expected_right = $signed(pcm_right);
            expected_left = (expected_left * volume * 2184) >>> 15;
            expected_right = (expected_right * volume * 2184) >>> 15;
            check(actual_volume === volume, "menu equals actual gain level");
            check(pcm_out_left === expected_left[23:0] && pcm_out_right === expected_right[23:0], "signed PCM follows menu at every level");
        end
    endtask
    function [7:0] channel_reference;
        input [7:0] value;
        input integer brightness, contrast_setting;
        integer adjusted, distance_value, sign_value;
        begin
            case (brightness)
                1: adjusted = value + 32;
                2: adjusted = value + 64;
                3: adjusted = value - 32;
                default: adjusted = value;
            endcase
            if (adjusted < 0) adjusted = 0;
            if (adjusted > 255) adjusted = 255;
            distance_value = adjusted - 128;
            sign_value = distance_value < 0 ? -1 : 1;
            if (distance_value < 0) distance_value = -distance_value;
            case (contrast_setting)
                1: adjusted = 128 + sign_value * (distance_value * 3 / 2);
                2: adjusted = 128 + sign_value * distance_value * 2;
                3: adjusted = adjusted / 2 + 64;
            endcase
            if (adjusted < 0) adjusted = 0;
            if (adjusted > 255) adjusted = 255;
            channel_reference = adjusted;
        end
    endfunction
    initial begin #200000000; $fatal(1, "menu top timeout"); end
endmodule
