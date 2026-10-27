`timescale 1ns/1ps

module tb_video_zoom;
    reg         clk     = 1'b0;
    reg         rst     = 1'b1;
    reg         zoom_en = 1'b1;
    reg         de      = 1'b0;
    reg         vs      = 1'b0;
    reg  [31:0] fifo    = 32'd0;
    wire        z_pop;
    wire [23:0] z_data;

    always #20 clk = ~clk;

    localparam integer HTOTAL = 800;
    localparam integer VTOTAL = 525;
    localparam integer HSTART = 160;

    integer hc = 0;
    integer vc = 0;
    integer frame = 0;

    always @(posedge clk) begin
        if (rst) begin
            hc <= 0; vc <= 0; de <= 1'b0; vs <= 1'b0;
        end
        else begin
            if (hc == HTOTAL-1) begin
                hc <= 0;
                if (vc == VTOTAL-1) begin
                    vc    <= 0;
                    frame <= frame + 1;
                end
                else vc <= vc + 1;
            end
            else hc <= hc + 1;
            de <= (hc >= HSTART) && (vc >= 35) && (vc < 515);
            vs <= (vc < 2);
        end
    end

    video_zoom dut (
        .clk       (clk),
        .rst       (rst),
        .zoom_en   (zoom_en),
        .col0      (10'd160),
        .de        (de),
        .vs        (vs),
        .fifo_data (fifo),
        .z_pop     (z_pop),
        .z_data    (z_data)
    );

    reg [20:0] de_p = 21'd0;
    always @(posedge clk) de_p <= {de_p[19:0], de};
    wire tde18 = de_p[18];
    wire tde19 = de_p[19];

    reg [9:0] mx     = 10'd0;
    reg [9:0] sj     = 10'd0;
    reg       tde18_d = 1'b0;
    reg       vs_d    = 1'b0;

    always @(posedge clk) begin
        tde18_d <= tde18;
        vs_d    <= vs;
        if (vs && !vs_d)            begin sj <= 10'd0; end
        else if (!tde18 && tde18_d) begin
            if (!dut.y18[0]) sj <= sj + 10'd1;
        end
        if (!tde18) mx <= 10'd0;
        else        mx <= mx + 10'd1;
    end

    function [23:0] pix;
        input [9:0] row;
        input [9:0] col;
        reg [7:0] rr;
        begin
            rr  = {4'd0, row[5:2]};
            pix = {row[7:0], col[7:0], (rr ^ {4'd0, col[7:4]})};
        end
    endfunction

    function [23:0] avg2f;
        input [23:0] a;
        input [23:0] b;
        integer s0;
        integer s1;
        integer s2;
        begin
            s0 = (a[23:16] * 1) + (b[23:16] * 1);
            s1 = (a[15:8]  * 1) + (b[15:8]  * 1);
            s2 = (a[7:0]   * 1) + (b[7:0]   * 1);
            avg2f = { s0[8:1], s1[8:1], s2[8:1] };
        end
    endfunction

    always @(posedge clk) begin
        if (z_pop) fifo <= {pix(sj, mx), 8'd0};
    end

    integer pops = 0;
    always @(posedge clk) if (z_pop) pops <= pops + 1;

    reg [9:0] last_wr_row = 10'd0;
    always @(posedge clk) if (dut.wr_en) last_wr_row <= dut.wr_row;

    reg [9:0]  dx = 10'd0;
    reg        tde19_d = 1'b0;
    reg        vs19_d  = 1'b0;
    reg [9:0]  dy = 10'd0;

    reg [23:0] shot [0:307199];
    integer    errors = 0;
    integer    checkedpix = 0;

    reg [9:0]  r_exp;
    reg [9:0]  m_exp;
    reg [23:0] h0;
    reg [23:0] h1;
    reg [23:0] want;

    always @(posedge clk) begin
        tde19_d <= tde19;
        vs19_d  <= vs;
        if (vs && !vs19_d)            dy <= 10'd0;
        else if (!tde19 && tde19_d)   dy <= dy + 10'd1;
        if (!tde19) dx <= 10'd0;
        else        dx <= dx + 10'd1;

        if (tde19) begin
            shot[dy*640 + dx] <= z_data;
            if ((frame == 3) && (dy <= 3) && (dx == 0))
                $display("DBG dy=%0d y18=%0d disp_row=%0d dob_cur=%h dob_nxt=%h wr_last_row=%0d",
                         dy, dut.y18, dut.disp_row, dut.dob_cur, dut.dob_nxt, last_wr_row);
            if (frame >= 3) begin
                if (dx == 0) begin
                    if ((dy < 2) && (dut.y18 > 10'd1)) begin
                        $display("GEOM dy=%0d y18=%0d not_blank", dy, dut.y18);
                        errors = errors + 1;
                    end
                    if ((dy >= 2) && (dut.disp_row !== ((dy - 2) >> 1))) begin
                        $display("GEOM dy=%0d disp_row=%0d want=%0d", dy, dut.disp_row, (dy - 2) >> 1);
                        errors = errors + 1;
                    end
                end
                if ((dy >= 2) && ((dx % 41) == 0)) begin
                    checkedpix = checkedpix + 1;
                    r_exp = (dy - 2) >> 1;
                    m_exp = dx >> 1;
                    h0 = dx[0] ? avg2f(pix(r_exp, 10'd160 + m_exp), pix(r_exp, 10'd161 + m_exp))
                               : pix(r_exp, 10'd160 + m_exp);
                    h1 = dx[0] ? avg2f(pix(r_exp + 10'd1, 10'd160 + m_exp), pix(r_exp + 10'd1, 10'd161 + m_exp))
                               : pix(r_exp + 10'd1, 10'd160 + m_exp);
                    want = dy[0] ? avg2f(h0, h1) : h0;
                    if (z_data !== want) begin
                        if (errors < 12)
                            $display("MISMATCH y=%0d x=%0d got=%h want=%h", dy, dx, z_data, want);
                        errors = errors + 1;
                    end
                end
            end
        end
    end

    integer fd;
    integer y;
    integer x;
    initial begin
        #200 rst = 1'b0;
        #(40 * HTOTAL * VTOTAL * 4);
        $display("frames=%0d pops=%0d checked=%0d errors=%0d", frame, pops, checkedpix, errors);
        fd = $fopen("frame_zoom.ppm", "wb");
        $fwrite(fd, "P6\n640 480\n255\n");
        for (y = 0; y < 480; y = y + 1)
            for (x = 0; x < 640; x = x + 1)
                $fwrite(fd, "%c%c%c", shot[y*640+x][23:16], shot[y*640+x][15:8], shot[y*640+x][7:0]);
        $fclose(fd);
        $display("ppm written");
        if (errors == 0) $display("PASS tb_video_zoom");
        else             $display("FAIL tb_video_zoom errors=%0d", errors);
        $finish;
    end
endmodule
