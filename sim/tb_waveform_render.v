`timescale 1ns/1ps
module tb_waveform_render;
    reg clk, rst, vs, de;
    reg [9:0] x, y;
    reg [23:0] rgb;
    wire out_vs, out_de;
    wire [23:0] out_rgb;
    wire rd_en;
    wire [9:0] rd_addr;
    reg [7:0] rd_data;
    reg rd_valid;
    integer errors;

    waveform_render dut (
        .I_clk(clk), .I_rst(rst), .I_vs(vs), .I_de(de), .I_x(x), .I_y(y), .I_rgb(rgb),
        .O_vs(out_vs), .O_de(out_de), .O_rgb(out_rgb),
        .O_wave_rd_en(rd_en), .O_wave_rd_addr(rd_addr),
        .I_wave_rd_data(rd_data), .I_wave_rd_valid(rd_valid)
    );

    always #20 clk = ~clk;

    function [7:0] blend_bar;
        input [7:0] v;
        input [7:0] b;
        integer s;
        begin
            s = 12*b + 4*v + 8;
            blend_bar = s >> 4;
        end
    endfunction

    function [23:0] bar_rgb_ref;
        input [23:0] v;
        begin
            bar_rgb_ref = {blend_bar(v[23:16],8'hb7),blend_bar(v[15:8],8'hc5),blend_bar(v[7:0],8'hc8)};
        end
    endfunction

    function integer height_ref;
        input [7:0] amp;
        integer a;
        begin
            if (amp <= 2) height_ref = 0;
            else begin
                a = amp * 44 + 127;
                height_ref = a >> 8;
                if (height_ref < 1) height_ref = 1;
                if (height_ref > 44) height_ref = 44;
            end
        end
    endfunction

    task pixel;
        input [9:0] px, py;
        input [7:0] amp;
        input [23:0] base;
        input [23:0] expected;
        begin
            @(negedge clk);
            de=1'b1; x=px; y=py; rgb=base; rd_data=amp; rd_valid=1'b0;
            @(posedge clk);
            @(negedge clk);
            rd_valid=1'b1;
            @(posedge clk);
            #1;
            if (out_de !== 1'b1 || out_rgb !== expected) begin
                $display("FAIL bar x=%0d y=%0d amp=%0d got=%h exp=%h",px,py,amp,out_rgb,expected);
                errors=errors+1;
            end
            rd_valid=1'b0; de=1'b0;
            @(negedge clk);
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        clk=0; rst=1; vs=0; de=0; x=0; y=0; rgb=24'h102030; rd_data=0; rd_valid=0; errors=0;
        repeat(3) @(posedge clk);
        @(negedge clk); rst=0;

        pixel(10'd0,10'd383,8'd255,24'h102030,24'h102030);
        pixel(10'd0,10'd384,8'd255,24'h102030,bar_rgb_ref(24'h102030));
        pixel(10'd0,10'd427,8'd255,24'h102030,bar_rgb_ref(24'h102030));
        pixel(10'd0,10'd428,8'd255,24'h102030,24'h102030);
        pixel(10'd1,10'd427,8'd255,24'h102030,bar_rgb_ref(24'h102030));
        pixel(10'd2,10'd427,8'd255,24'h102030,24'h102030);
        pixel(10'd639,10'd427,8'd255,24'h102030,bar_rgb_ref(24'h102030));
        pixel(10'd0,10'd427,8'd2,24'h102030,24'h102030);
        pixel(10'd0,10'd427,8'd3,24'h102030,bar_rgb_ref(24'h102030));
        pixel(10'd0,10'd383,8'd128,24'h102030,24'h102030);
        pixel(10'd0,10'd405,8'd128,24'h102030,24'h102030);

        if (errors==0) $display("WAVEFORM_RENDER PASS");
        else $display("WAVEFORM_RENDER FAIL errors=%0d",errors);
        $finish;
    end
    initial begin
        #1000000;
        $display("WAVEFORM_RENDER TIMEOUT");
        $finish;
    end
endmodule
