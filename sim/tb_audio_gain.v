`timescale 1ns/1ps
module tb_audio_gain;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [3:0] lvl = 4'd0;
    reg signed [23:0] in_l = 24'sd1000000;
    reg signed [23:0] in_r = 24'sd1000000;
    wire signed [23:0] out_l, out_r;
    wire [3:0] vol_level;
    integer v;

    audio_volume_gain #(.DEFAULT_VOL(4'd15), .EXTERNAL_LEVEL(1)) u (
        .clk(clk), .rst_n(rst_n), .vol_up_pulse(1'b0), .vol_down_pulse(1'b0),
        .external_vol_level(lvl), .in_valid(1'b1),
        .in_left(in_l), .in_right(in_r),
        .out_left(out_l), .out_right(out_r), .vol_level(vol_level)
    );

    always #19.861 clk = ~clk;

    initial begin
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;
        for (v = 0; v <= 15; v = v + 1) begin
            lvl = v[3:0];
            @(posedge clk);
            #1;
            $display("vol=%2d gain_q15=%5d out=%8d  相对满档=%6.2f dB",
                     v, u.gain_q15, out_l,
                     (u.gain_q15 == 0) ? -99.0 : 20.0 * $log10(u.gain_q15 / 8775.0));
        end
        $finish;
    end
endmodule
