`timescale 1ns/1ps
module tb_status_bar_render;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1;
    reg vs  = 1'b0;
    wire de  = 1'b0;

    reg [87:0] track_name;
    reg [3:0]  vol_level;
    reg [1:0]  img_idx;
    reg        auto_en;

    wire        sb_req_valid;
    wire [6:0]  sb_req_ascii;
    wire [7:0]  sb_req_x;
    wire [3:0]  sb_req_y;
    wire [1:0]  sb_req_type;
    wire        sb_req_ready;
    wire        font_rd_en;
    wire [6:0]  font_ascii;
    wire [2:0]  font_row;
    wire [7:0]  font_rd_data;
    wire        font_rd_valid;
    wire        buf_wr_en;
    wire [7:0]  buf_wr_x;
    wire [3:0]  buf_wr_y;
    wire [1:0]  buf_wr_data;
    wire        busy;
    wire [15:0] dirty_row;
    reg         rd_en = 1'b0;
    reg  [7:0]  rd_x = 8'd0;
    reg  [3:0]  rd_y = 4'd0;
    wire [1:0]  rd_data;
    wire        rd_valid;

    reg [7:0] reference [0:1023];
    integer failures = 0;
    integer r, c, k, guard;
    reg [1:0] vv;

    reg [87:0] sname;
    reg [3:0]  svol;
    reg [1:0]  simg;
    reg        sauto;
    reg [6:0]  sh;
    reg [5:0]  sm, ss;

    reg        monitor = 1'b0;
    integer    idle_wr = 0;
    always @(posedge clk) if (monitor && buf_wr_en) idle_wr = idle_wr + 1;

    font_rom u_font (
        .clk(clk), .rst(rst), .rd_en(font_rd_en),
        .ascii(font_ascii), .row(font_row),
        .rd_data(font_rd_data), .rd_valid(font_rd_valid)
    );
    osd_buffer u_buf (
        .clk(clk), .rst(rst),
        .wr_en(buf_wr_en), .wr_x(buf_wr_x), .wr_y(buf_wr_y), .wr_data(buf_wr_data),
        .rd_en(rd_en), .rd_x(rd_x), .rd_y(rd_y),
        .rd_data(rd_data), .rd_valid(rd_valid)
    );
    osd_renderer u_rend (
        .clk(clk), .rst(rst), .vs(vs), .de(de),
        .req_valid(sb_req_valid), .req_ascii(sb_req_ascii), .req_x(sb_req_x),
        .req_y(sb_req_y), .req_type(sb_req_type), .req_ready(sb_req_ready),
        .font_rd_en(font_rd_en), .font_ascii(font_ascii), .font_row(font_row),
        .font_rd_data(font_rd_data), .font_rd_valid(font_rd_valid),
        .buf_wr_en(buf_wr_en), .buf_wr_x(buf_wr_x), .buf_wr_y(buf_wr_y),
        .buf_wr_data(buf_wr_data), .dirty_clr(1'b0),
        .busy(busy), .dirty_row(dirty_row)
    );
    status_bar_render u_sb (
        .clk(clk), .rst(rst), .vs(vs),
        .track_name(track_name), .vol_level(vol_level),
        .img_idx(img_idx), .auto_en(auto_en),
        .req_valid(sb_req_valid), .req_ascii(sb_req_ascii), .req_x(sb_req_x),
        .req_y(sb_req_y), .req_type(sb_req_type), .req_ready(sb_req_ready)
    );

    reg fast_vs = 1'b0;
    wire       f_req_valid;
    wire [6:0] f_req_ascii;
    wire [7:0] f_req_x;
    wire [3:0] f_req_y;
    wire [1:0] f_req_type;
    status_bar_render #(
        .P_FRAMES_PER_SEC(6'd1),
        .P_SEC_MAX(6'd1),
        .P_MIN_MAX(6'd1)
    ) u_sb_fast (
        .clk(clk), .rst(rst), .vs(fast_vs),
        .track_name(88'd0), .vol_level(4'd12),
        .img_idx(2'd0), .auto_en(1'b1),
        .req_valid(f_req_valid), .req_ascii(f_req_ascii), .req_x(f_req_x),
        .req_y(f_req_y), .req_type(f_req_type), .req_ready(1'b1)
    );

    initial begin
        vs = 1'b0;
        forever begin
            repeat (4000) @(posedge clk);
            vs = 1'b1;
            repeat (4) @(posedge clk);
            vs = 1'b0;
        end
    end

    task read_pixel;
        input [11:0] addr;
        output [1:0] val;
        begin
            @(negedge clk);
            rd_en = 1'b1; rd_y = addr[11:8]; rd_x = addr[7:0];
            @(posedge clk);
            #1;
            val = rd_data;
            @(negedge clk);
            rd_en = 1'b0;
        end
    endtask

    task verify_char;
        input [7:0] cx;
        input [3:0] cy;
        input [6:0] asc;
        input [1:0] typ;
        reg [11:0] addr;
        reg [7:0]  g;
        reg [1:0]  val;
        reg [1:0]  expect;
        begin
            for (r = 0; r < 8; r = r + 1) begin
                for (c = 0; c < 8; c = c + 1) begin
                    addr = {cy + r[3:0], cx[4:0], c[2:0]};
                    g = reference[{asc, r[2:0]}];
                    expect = g[7-c] ? typ : 2'b00;
                    read_pixel(addr, val);
                    if (val !== expect) begin
                        $display("FAIL col=%0d asc=%0d r=%0d c=%0d expect=%b actual=%b",
                                 cx, asc, r, c, expect, val);
                        failures = failures + 1;
                    end
                end
            end
        end
    endtask

    function [3:0] f_tens;
        input [6:0] v;
        begin
            if (v >= 7'd90) f_tens = 4'd9;
            else if (v >= 7'd80) f_tens = 4'd8;
            else if (v >= 7'd70) f_tens = 4'd7;
            else if (v >= 7'd60) f_tens = 4'd6;
            else if (v >= 7'd50) f_tens = 4'd5;
            else if (v >= 7'd40) f_tens = 4'd4;
            else if (v >= 7'd30) f_tens = 4'd3;
            else if (v >= 7'd20) f_tens = 4'd2;
            else if (v >= 7'd10) f_tens = 4'd1;
            else f_tens = 4'd0;
        end
    endfunction
    function [3:0] f_ones;
        input [6:0] v;
        input [3:0] t;
        begin f_ones = v - {t, 3'd0} - {t, 1'd0}; end
    endfunction

    function [6:0] exp_ascii;
        input [5:0] col;
        reg [3:0] vt, vo, ht, ho, mt, mo, st, so;
        begin
            vt = (svol >= 4'd10) ? 4'd1 : 4'd0;
            vo = svol - (vt[0] ? 4'd10 : 4'd0);
            ht = f_tens(sh); ho = f_ones(sh, ht);
            mt = f_tens({1'b0, sm}); mo = f_ones({1'b0, sm}, mt);
            st = f_tens({1'b0, ss}); so = f_ones({1'b0, ss}, st);
            case (col)
                6'd0:  exp_ascii = sname[86:80];
                6'd1:  exp_ascii = sname[78:72];
                6'd2:  exp_ascii = sname[70:64];
                6'd3:  exp_ascii = sname[62:56];
                6'd4:  exp_ascii = sname[54:48];
                6'd5:  exp_ascii = sname[46:40];
                6'd6:  exp_ascii = sname[38:32];
                6'd7:  exp_ascii = sname[30:24];
                6'd8:  exp_ascii = 7'd86;
                6'd9:  exp_ascii = 7'd48 + {3'd0, vt};
                6'd10: exp_ascii = 7'd48 + {3'd0, vo};
                6'd11: exp_ascii = 7'd32;
                6'd12: exp_ascii = 7'd48 + {3'd0, ht};
                6'd13: exp_ascii = 7'd48 + {3'd0, ho};
                6'd14: exp_ascii = 7'd58;
                6'd15: exp_ascii = 7'd48 + {3'd0, mt};
                6'd16: exp_ascii = 7'd48 + {3'd0, mo};
                6'd17: exp_ascii = 7'd58;
                6'd18: exp_ascii = 7'd48 + {3'd0, st};
                6'd19: exp_ascii = 7'd48 + {3'd0, so};
                6'd20: exp_ascii = 7'd32;
                6'd21: exp_ascii = 7'd80;
                6'd22: exp_ascii = 7'd73;
                6'd23: exp_ascii = 7'd67;
                6'd24: exp_ascii = 7'd49 + {5'd0, simg};
                6'd25: exp_ascii = 7'd47;
                6'd26: exp_ascii = 7'd52;
                6'd27: exp_ascii = 7'd32;
                6'd28: exp_ascii = sauto ? 7'd65 : 7'd77;
                6'd29: exp_ascii = sauto ? 7'd85 : 7'd65;
                6'd30: exp_ascii = sauto ? 7'd84 : 7'd78;
                6'd31: exp_ascii = sauto ? 7'd79 : 7'd32;
                default: exp_ascii = 7'd32;
            endcase
        end
    endfunction

    task sample_snap;
        begin
            sname = u_sb.snap_name; svol = u_sb.snap_vol;
            simg  = u_sb.snap_img;  sauto = u_sb.snap_auto;
            sh = u_sb.snap_hour; sm = u_sb.snap_min; ss = u_sb.snap_sec;
        end
    endtask

    task verify_cols;
        input integer c0;
        input integer c1;
        integer i;
        begin
            for (i = c0; i <= c1; i = i + 1)
                verify_char(i[7:0], 4'd8, exp_ascii(i[5:0]), 2'b10);
        end
    endtask

    task wait_refresh;
        begin
            @(posedge clk); #1;
            guard = 0;
            while (u_sb.sending !== 1'b1 && guard < 50000) begin
                @(posedge clk); guard = guard + 1;
            end
            while (u_sb.sending !== 1'b0) @(posedge clk);
            while (busy !== 1'b0) @(posedge clk);
            repeat (4) @(posedge clk);
        end
    endtask

    task pulse_fast_vs;
        begin
            @(negedge clk); fast_vs = 1'b1;
            repeat (4) @(negedge clk);
            fast_vs = 1'b0;
            repeat (4) @(negedge clk);
        end
    endtask

    initial begin
        $readmemh("font_data.mem", reference);
        track_name = {8'd84,8'd82,8'd65,8'd67,8'd75,8'd48,8'd49,8'd32,
                     8'd82,8'd65,8'd87};
        vol_level = 4'd12;
        img_idx   = 2'd0;
        auto_en   = 1'b1;
        repeat (4) @(negedge clk);
        rst = 1'b0;
        repeat (30000) @(posedge clk);
        @(posedge clk);
        while (u_sb.sending !== 1'b0) @(posedge clk);
        while (busy !== 1'b0) @(posedge clk);
        repeat (4) @(posedge clk);
        sample_snap;

        if (sh !== 7'd0 || sm !== 6'd0 || ss !== 6'd0) begin
            $display("FAIL init time %0d:%0d:%0d", sh, sm, ss);
            failures = failures + 1;
        end
        if (simg !== 2'd0 || sauto !== 1'b1 || svol !== 4'd12) begin
            $display("FAIL init fields img=%b auto=%b vol=%0d", simg, sauto, svol);
            failures = failures + 1;
        end
        verify_cols(0, 31);

        for (k = 0; k < 32; k = k + 1) begin
            read_pixel({4'd0, k[4:0], 3'd0}, vv);
            if (vv !== 2'b00) begin
                $display("FAIL upper row not clean at col=%0d val=%b", k, vv);
                failures = failures + 1;
            end
        end

        img_idx = 2'd1;
        wait_refresh;
        sample_snap;
        if (simg !== 2'd1) begin
            $display("FAIL img not updated %b", simg);
            failures = failures + 1;
        end
        verify_cols(21, 24);

        auto_en = 1'b0;
        wait_refresh;
        sample_snap;
        if (sauto !== 1'b0) begin
            $display("FAIL auto not updated");
            failures = failures + 1;
        end
        verify_cols(28, 31);

        vol_level = 4'd0;
        wait_refresh;
        sample_snap;
        if (svol !== 4'd0) begin
            $display("FAIL vol not updated %0d", svol);
            failures = failures + 1;
        end
        verify_cols(8, 10);

        track_name = {8'd84,8'd82,8'd65,8'd67,8'd75,8'd48,8'd50,8'd32,
                      8'd82,8'd65,8'd87};
        wait_refresh;
        sample_snap;
        if (sname !== track_name) begin
            $display("FAIL name not updated");
            failures = failures + 1;
        end
        verify_cols(0, 7);

        k = u_sb.second;
        guard = 0;
        while (u_sb.second === k[5:0] && guard < 300000) begin
            @(posedge clk); guard = guard + 1;
        end
        wait_refresh;
        sample_snap;
        if (ss !== ((k + 1) % 60)) begin
            $display("FAIL second step from=%0d to=%0d", k, ss);
            failures = failures + 1;
        end
        verify_cols(12, 19);

        monitor = 1'b1;
        idle_wr = 0;
        repeat (12000) @(posedge clk);
        monitor = 1'b0;
        if (idle_wr !== 0) begin
            $display("FAIL unexpected buffer writes while idle=%0d", idle_wr);
            failures = failures + 1;
        end

        for (k = 0; k < 8; k = k + 1) pulse_fast_vs;
        if (u_sb_fast.hour !== 7'd1 || u_sb_fast.minute !== 6'd0 ||
            u_sb_fast.second !== 6'd0) begin
            $display("FAIL fast carry h=%0d m=%0d s=%0d",
                     u_sb_fast.hour, u_sb_fast.minute, u_sb_fast.second);
            failures = failures + 1;
        end
        for (k = 0; k < 8; k = k + 1) pulse_fast_vs;
        if (u_sb_fast.hour !== 7'd2) begin
            $display("FAIL fast hour2 h=%0d", u_sb_fast.hour);
            failures = failures + 1;
        end

        if (failures == 0) $display("PASS tb_status_bar_render");
        else $fatal(1, "tb_status_bar_render failures=%0d", failures);
        $finish;
    end
endmodule
