`timescale 1ns/1ps
// 实测经 I2S 环回恢复出的 audio_valid(48kHz) 节拍均匀度
// 真实频率：audio_mclk=12.288MHz(81.38ns)，video_clk=25MHz(40ns)
// 理想相邻 valid 间隔 = 25e6/48e3 = 520.83 video 周期（应在 520/521 间交替）
module tb_audio_strobe_jitter;
    reg mclk = 0, vclk = 0, rst = 1;
    always #40.69 mclk = ~mclk;   // 12.288MHz
    always #20.00 vclk = ~vclk;   // 25MHz

    wire bclk, lrck, dout;
    hdmi_audio_tone_i2s_64fs u_tone(
        .I_mclk(mclk), .I_rst(rst),
        .O_i2s_BCLK(bclk), .O_i2s_LRCK(lrck), .O_i2s_DOUT(dout));

    wire        valid;
    wire [23:0] ldata, rdata;
    I2S_receiver u_rx(
        .I_clk(vclk), .I_rst(rst),
        .I_i2s_BCLK(bclk), .I_i2s_LRCK(lrck), .I_i2s_DOUT(dout),
        .O_audio_valid(valid), .O_audio_left_data(ldata), .O_audio_right_data(rdata));

    integer vcnt = 0;
    integer last = 0;
    integer n = 0, d;
    integer dmin = 99999, dmax = 0;
    integer bad = 0;        // 间隔不在 519..522
    integer verybad = 0;    // 间隔偏离 >=5（明显丢/补拍）
    integer hist_520 = 0, hist_521 = 0, hist_other = 0;

    always @(posedge vclk) begin
        vcnt <= vcnt + 1;
        if (valid) begin
            if (n > 0) begin
                d = vcnt - last;
                if (d < dmin) dmin = d;
                if (d > dmax) dmax = d;
                if (d < 519 || d > 522) bad = bad + 1;
                if (d < 516 || d > 526) verybad = verybad + 1;
                if (d == 520) hist_520 = hist_520 + 1;
                else if (d == 521) hist_521 = hist_521 + 1;
                else hist_other = hist_other + 1;
            end
            last <= vcnt;
            n <= n + 1;
        end
    end

    // 直接在 mclk 域数：一个 LRCK 完整周期含多少 mclk；BCLK 半周期含多少 mclk
    integer mc = 0, lr_prev = 0, lr_start = 0, lr_per = 0, lr_got = 0;
    integer bc_prev = 0, bc_start = 0, bc_per = 0, bc_got = 0;
    always @(posedge mclk) begin
        mc <= mc + 1;
        // LRCK 完整周期（相邻两次同沿，用下降沿）
        if (lr_prev==1 && lrck==0) begin
            if (lr_start!=0 && lr_got<5) begin
                lr_per <= mc - lr_start; lr_got <= lr_got+1;
            end
            lr_start <= mc;
        end
        lr_prev <= lrck;
        // BCLK 半周期（相邻下降沿）
        if (bc_prev==1 && bclk==0) begin
            if (bc_start!=0 && bc_got<5) begin
                bc_per <= mc - bc_start; bc_got <= bc_got+1;
            end
            bc_start <= mc;
        end
        bc_prev <= bclk;
    end

    // 原始 LRCK 下降沿在 video 域的间隔（绕过接收端）
    integer vlr_prev = 0, vlr_last = 0, vlr_d = 0, vlr_min = 9999, vlr_max = 0, vlr_n = 0;
    always @(posedge vclk) begin
        if (vlr_prev==1 && lrck==0) begin
            if (vlr_last!=0 && vlr_n<200) begin
                vlr_d = vcnt - vlr_last;
                if (vlr_d<vlr_min) vlr_min=vlr_d;
                if (vlr_d>vlr_max) vlr_max=vlr_d;
                vlr_n = vlr_n+1;
            end
            vlr_last <= vcnt;
        end
        vlr_prev <= lrck;
    end

    initial begin
        #500 rst = 0;
        #4000000;   // 约 4000us，~192 帧
        $display("RAW LRCK video interval min=%0d max=%0d", vlr_min, vlr_max);
        $display("LRCK full period in mclk=%0d (expect 256); BCLK full in mclk=%0d (expect 2)", lr_per, bc_per);
        $display("pulses=%0d dmin=%0d dmax=%0d", n, dmin, dmax);
        $display("interval 520:%0d  521:%0d  other:%0d", hist_520, hist_521, hist_other);
        $display("bad(out of 519..522)=%0d   verybad(out of 516..526)=%0d", bad, verybad);
        $finish;
    end
endmodule
