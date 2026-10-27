`timescale 1ns/1ps
module tb_spec_render;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg vs = 1'b0;
    reg de = 1'b0;
    reg [9:0] x = 10'd0;
    reg [9:0] y = 10'd0;
    reg [239:0] bands = 240'd0;
    reg [1:0] lvl = 2'd0;
    wire o_vs, o_de;
    wire [23:0] o_rgb;

    integer f;

    spectrum_render u_dut (
        .I_clk(clk), .I_rst(rst), .I_vs(vs), .I_de(de), .I_x(x), .I_y(y),
        .I_rgb(24'd0), .I_bands(bands), .I_emph_lvl(lvl),
        .O_vs(o_vs), .O_de(o_de), .O_rgb(o_rgb)
    );

    always #19.861 clk = ~clk;

    initial begin
        bands = 240'd0;
        bands[6*10 +: 6] = 6'd20;
        repeat (5) @(posedge clk);
        rst <= 1'b0;
        x = 10'd166;
        de = 1'b1;
        y = 10'd441;
        for (f = 0; f < 42; f = f + 1) begin
            lvl = f[1:0];
            @(posedge clk);
            #1;
            $display("f=%0d lvl=%0d eph=%0d b10=%0d b11=%0d", f, lvl, u_dut.eph,
                     u_dut.band_h, u_dut.band_he);
            vs = 1'b1; @(posedge clk); vs = 1'b0;
            repeat (1000) @(posedge clk);
        end
        $finish;
    end
endmodule
