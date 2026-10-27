`timescale 1ns/1ps
module tb_osd_buffer_overlay;

    localparam [23:0] BG = 24'h808080;
    localparam [23:0] BANNER      = 24'h101820;
    localparam [23:0] EDGE        = 24'h00D0FF;
    localparam [23:0] PANEL       = 24'h1A1D23;
    localparam [23:0] TXT         = 24'hF0EDE8;
    localparam [23:0] HIGHLIGHT   = 24'hE8A838;

    reg         clk;
    reg         rst;
    reg         I_de;
    reg         I_vs;
    reg  [23:0] I_rgb;
    reg  [2:0]  I_ui_alpha;
    wire        O_de;
    wire        O_vs;
    wire [23:0] O_rgb;

    wire        rd_en;
    wire [7:0]  rd_x;
    wire [3:0]  rd_y;
    wire [1:0]  rd_data;
    wire        rd_valid;

    reg         wr_en;
    reg  [7:0]  wr_x;
    reg  [3:0]  wr_y;
    reg  [1:0]  wr_data;

    integer row, col;
    integer wx, wy;
    integer errors;
    integer checked;
    integer ox, oy;
    reg     o_de_d, o_vs_d;
    reg     monitor_en;
    integer tol;

    osd_buffer u_buf (
        .clk     (clk),
        .rst     (rst),
        .wr_en   (wr_en),
        .wr_x    (wr_x),
        .wr_y    (wr_y),
        .wr_data (wr_data),
        .rd_en   (rd_en),
        .rd_x    (rd_x),
        .rd_y    (rd_y),
        .rd_data (rd_data),
        .rd_valid(rd_valid)
    );

    osd_buffer_overlay u_dut (
        .I_clk (clk),
        .I_rst (rst),
        .I_de  (I_de),
        .I_vs  (I_vs),
        .I_rgb (I_rgb),
        .I_ui_alpha(I_ui_alpha),
        .O_de  (O_de),
        .O_vs  (O_vs),
        .O_rgb (O_rgb),
        .rd_en (rd_en),
        .rd_x  (rd_x),
        .rd_y  (rd_y),
        .rd_data(rd_data)
    );

    initial clk = 1'b0;
    always #20 clk = ~clk;

    task wr_buf;
        input [7:0] wx_i;
        input [3:0] wy_i;
        input [1:0] wd_i;
        begin
            @(negedge clk);
            wr_en   = 1'b1;
            wr_x    = wx_i;
            wr_y    = wy_i;
            wr_data = wd_i;
            @(posedge clk);
            @(negedge clk);
            wr_en   = 1'b0;
        end
    endtask

    function [7:0] ref_mix;
        input [7:0] bg;
        input [7:0] fg;
        input [3:0] a;
        integer v;
        begin
            v = (bg * (8 - a) + fg * a) / 8;
            ref_mix = v[7:0];
        end
    endfunction

    function [7:0] ref_mix75;
        input [7:0] bg;
        input [7:0] fg;
        integer v;
        begin
            v = (fg * 3 + bg) / 4;
            ref_mix75 = v[7:0];
        end
    endfunction

    function [7:0] ref_mix35;
        input [7:0] bg;
        input [7:0] fg;
        integer v;
        begin
            v = (fg * 3 + bg * 5) / 8;
            ref_mix35 = v[7:0];
        end
    endfunction

    function [23:0] mix3;
        input [23:0] bg;
        input [23:0] fg;
        input [3:0]  a;
        begin
            mix3 = {ref_mix(bg[23:16], fg[23:16], a),
                    ref_mix(bg[15:8],  fg[15:8],  a),
                    ref_mix(bg[7:0],   fg[7:0],   a)};
        end
    endfunction

    function [23:0] mix75_3;
        input [23:0] bg;
        input [23:0] fg;
        begin
            mix75_3 = {ref_mix75(bg[23:16], fg[23:16]),
                       ref_mix75(bg[15:8],  fg[15:8]),
                       ref_mix75(bg[7:0],   fg[7:0])};
        end
    endfunction

    function [23:0] mix35_3;
        input [23:0] bg;
        input [23:0] fg;
        begin
            mix35_3 = {ref_mix35(bg[23:16], fg[23:16]),
                       ref_mix35(bg[15:8],  fg[15:8]),
                       ref_mix35(bg[7:0],   fg[7:0])};
        end
    endfunction

    function [23:0] expected;
        input integer px;
        input integer py;
        input [2:0]   alpha;
        integer ai;
        integer bx, by;
        reg [1:0] t;
        reg [23:0] bgl;
        reg [23:0] fgl;
        begin
            ai = (alpha == 3'd7) ? 8 : alpha;
            t  = 2'b00;

            if ((py >= 432) && (py < 472)) begin
                if ((py < 434) || (py >= 470))
                    bgl = mix3(BG, EDGE, ai[3:0]);
                else
                    bgl = mix3(BG, BANNER, ai[3:0]);
            end else begin
                bgl = BG;
            end

            if ((px >= 64) && (px < 576) && (py >= 444) && (py < 460)) begin
                bx = (px - 64) >> 1;
                by = (py - 444) >> 1;
                if      ((bx == 0) && (by == 0)) t = 2'b01;
                else if ((bx == 1) && (by == 0)) t = 2'b10;
                else if ((bx == 2) && (by == 0)) t = 2'b11;
                else                              t = 2'b00;
            end

            if (t == 2'b10)
                fgl = TXT;
            else if (t == 2'b01)
                fgl = mix75_3(bgl, PANEL);
            else if (t == 2'b11)
                fgl = mix35_3(bgl, HIGHLIGHT);
            else
                fgl = bgl;

            if ((py >= 432) && (py < 472))
                expected = mix3(bgl, fgl, ai[3:0]);
            else
                expected = BG;
        end
    endfunction

    task check_pixel;
        input integer px;
        input integer py;
        reg [23:0] exp;
        integer dr, dg, db;
        begin
            exp = expected(px, py, I_ui_alpha);
            checked = checked + 1;
            dr = O_rgb[23:16] - exp[23:16];
            dg = O_rgb[15:8]  - exp[15:8];
            db = O_rgb[7:0]   - exp[7:0];
            if ((dr < 0) || (dr > tol) || (dr < -tol) ||
                (dg < -tol) || (dg > tol) ||
                (db < -tol) || (db > tol)) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("MISMATCH a=%0d x=%0d y=%0d got=%06h exp=%06h",
                             I_ui_alpha, px, py, O_rgb, exp);
            end
        end
    endtask

    task send_frame;
        begin
            @(negedge clk); I_vs = 1'b1;
            repeat (3) @(posedge clk);
            @(negedge clk); I_vs = 1'b0;
            repeat (4) @(posedge clk);
            for (row = 0; row < 480; row = row + 1) begin
                @(negedge clk); I_de = 1'b0;
                repeat (3) @(posedge clk);
                for (col = 0; col < 640; col = col + 1) begin
                    @(negedge clk);
                    I_de  = 1'b1;
                    I_rgb = BG;
                end
                @(negedge clk); I_de = 1'b0;
            end
            repeat (10) @(posedge clk);
        end
    endtask

    always @(posedge clk) begin
        #1;
        if (rst) begin
            ox = 0; oy = 0; o_de_d = 1'b0; o_vs_d = 1'b0;
        end else if (monitor_en) begin
            if (o_vs_d !== O_vs) begin
                ox = 0; oy = 0;
            end
            if (O_de) begin
                if (!o_de_d) ox = 0;
                check_pixel(ox, oy);
                ox = ox + 1;
            end else begin
                if (o_de_d) oy = oy + 1;
            end
            o_de_d = O_de;
            o_vs_d = O_vs;
        end else begin
            ox = 0; oy = 0; o_de_d = O_de; o_vs_d = O_vs;
        end
    end

    initial begin
        rst = 1'b1;
        I_de = 1'b0; I_vs = 1'b0; I_rgb = BG; I_ui_alpha = 3'd7;
        wr_en = 1'b0; wr_x = 8'd0; wr_y = 4'd0; wr_data = 2'd0;
        errors = 0; checked = 0; tol = 0;
        ox = 0; oy = 0; o_de_d = 1'b0; o_vs_d = 1'b0;
        monitor_en = 1'b0;

        repeat (5) @(posedge clk);
        @(negedge clk); rst = 1'b0;
        repeat (3) @(posedge clk);

        for (wy = 0; wy < 16; wy = wy + 1)
            for (wx = 0; wx < 256; wx = wx + 1)
                wr_buf(wx, wy, 2'b00);
        wr_buf(8'd0, 4'd8, 2'b01);
        wr_buf(8'd1, 4'd8, 2'b10);
        wr_buf(8'd2, 4'd8, 2'b11);
        wr_buf(8'd3, 4'd8, 2'b00);

        @(negedge clk); rst = 1'b1; I_de = 1'b0; I_rgb = BG;
        repeat (3) @(posedge clk);
        @(negedge clk); rst = 1'b0;
        repeat (3) @(posedge clk);

        monitor_en = 1'b1;
        I_ui_alpha = 3'd7; tol = 0;
        send_frame;
        $display("frame a=7 done checked=%0d errors=%0d", checked, errors);

        I_ui_alpha = 3'd0; tol = 0;
        send_frame;
        $display("frame a=0 done checked=%0d errors=%0d", checked, errors);

        I_ui_alpha = 3'd4; tol = 1;
        send_frame;
        $display("frame a=4 done checked=%0d errors=%0d", checked, errors);
        monitor_en = 1'b0;

        if ((errors == 0) && (checked == 640*480*3))
            $display("PASS tb_osd_buffer_overlay");
        else
            $display("FAIL tb_osd_buffer_overlay errors=%0d checked=%0d", errors, checked);
        $finish;
    end

endmodule
