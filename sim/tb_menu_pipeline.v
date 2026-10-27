`timescale 1ns/1ps
module tb_menu_pipeline;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1;
    reg vs = 0;
    reg de = 0;
    reg vis = 1;
    reg [2:0] selected = 0;
    reg redraw = 0;
    reg sb_valid = 0;
    wire menu_valid, menu_busy, menu_ready, ready, clear_done, render_busy;
    wire [6:0] menu_ascii, menu_y, font_ascii, wr_y;
    wire [7:0] menu_x, wr_x;
    wire [1:0] menu_type, wr_data;
    wire menu_fill, font_en, f5_valid, f8_valid, wr_en;
    wire [2:0] font_row;
    wire [7:0] f5_data, f8_data;
    wire font_mode;
    wire request_valid = menu_busy ? menu_valid : sb_valid;
    wire [6:0] request_ascii = menu_busy ? menu_ascii : 7'd65;
    wire [7:0] request_x = menu_busy ? menu_x : 8'd31;
    wire [6:0] request_y = menu_busy ? menu_y : 7'd72;
    wire [1:0] request_type = menu_busy ? menu_type : 2'b10;
    wire request_fill = menu_busy && menu_fill;
    wire [7:0] font_data = font_mode ? f5_data : f8_data;
    wire font_valid = font_mode ? f5_valid : f8_valid;
    reg rd_en = 0;
    reg [7:0] rd_x = 0;
    reg [6:0] rd_y = 0;
    wire [1:0] rd_data;
    wire rd_valid;
    reg [7:0] ref5 [0:1023];
    reg [7:0] ref8 [0:1023];
    reg [151:0] expected_line;
    reg [7:0] expected_char;
    reg [1:0] expected_pixel;
    integer failures = 0;
    integer checked = 0;
    integer requests = 0;
    integer r, slot, y, x;
    integer selection_arg;
    integer interrupted = 0;
    reg scan_mode = 0;
    reg overlay_rst = 1;
    reg scan_de = 0;
    reg scan_vs = 0;
    reg [23:0] scan_rgb = 0;
    wire overlay_de, overlay_vs, overlay_rd_en;
    wire [23:0] overlay_rgb;
    wire [7:0] overlay_rd_x;
    wire [6:0] overlay_rd_y;
    reg [23:0] screen_expected;
    integer screen_checked = 0;
    integer sx, sy;

`ifdef LEGACY_FONT_SELECT
    assign font_mode = menu_busy;
`endif

    assign menu_ready = ready && menu_busy;
    menu_renderer menu (
        .clk(clk), .rst(rst), .vis(vis), .buf_ready(clear_done),
        .redraw(redraw), .p_volume(4'd8), .p_bright(2'd2),
        .p_contrast(2'd2), .p_trans(3'd0), .p_auto(1'b1),
        .p_period(4'd3), .p_info(1'b1),
        .sel_row(selected), .req_valid(menu_valid), .req_ascii(menu_ascii),
        .req_x(menu_x), .req_y(menu_y), .req_type(menu_type),
        .req_fill(menu_fill), .req_ready(menu_ready), .busy(menu_busy)
    );
    osd_renderer renderer (
        .clk(clk), .rst(rst), .vs(vs), .de(de),
        .req_valid(request_valid), .req_ascii(request_ascii),
        .req_x(request_x), .req_y(request_y), .req_type(request_type),
        .req_w5(menu_busy), .req_fill(request_fill), .req_ready(ready),
        .font_rd_en(font_en), .font_ascii(font_ascii), .font_row(font_row),
`ifndef LEGACY_FONT_SELECT
        .font_w5(font_mode),
`endif
        .font_rd_data(font_data), .font_rd_valid(font_valid),
        .buf_wr_en(wr_en), .buf_wr_x(wr_x), .buf_wr_y(wr_y),
        .buf_wr_data(wr_data), .dirty_clr(1'b0), .busy(render_busy),
        .dirty_row(), .clr_done_o(clear_done)
    );
    font5x7_rom font5 (.clk(clk), .rst(rst), .rd_en(font_en),
        .ascii(font_ascii), .row(font_row), .rd_data(f5_data), .rd_valid(f5_valid));
    font_rom font8 (.clk(clk), .rst(rst), .rd_en(font_en),
        .ascii(font_ascii), .row(font_row), .rd_data(f8_data), .rd_valid(f8_valid));
    osd_buffer buffer (.clk(clk), .rst(rst), .wr_en(wr_en), .wr_x(wr_x),
        .wr_y(wr_y), .wr_data(wr_data), .rd_en(scan_mode ? overlay_rd_en : rd_en),
        .rd_x(scan_mode ? overlay_rd_x : rd_x), .rd_y(scan_mode ? overlay_rd_y : rd_y),
        .rd_data(rd_data), .rd_valid(rd_valid));
    osd_buffer_overlay overlay (
        .I_clk(clk), .I_rst(overlay_rst), .I_de(scan_de), .I_vs(scan_vs),
        .I_rgb(scan_rgb), .I_ui_alpha(3'd7), .I_panel_vis(1'b1),
        .O_de(overlay_de), .O_vs(overlay_vs), .O_rgb(overlay_rgb),
        .rd_en(overlay_rd_en), .rd_x(overlay_rd_x), .rd_y(overlay_rd_y),
        .rd_data(rd_data));

    function [23:0] expected_rgb;
        input integer px, py;
        integer bx, by, line_id, slot_id, gx, gy;
        reg [151:0] line_text;
        reg [7:0] ch;
        begin
            expected_rgb = 24'h808080;
            if (py >= 432 && py < 472) begin
                expected_rgb = (py < 434 || py >= 470) ? 24'h00D0FF : 24'h101820;
                if (px >= 560 && px < 576 && py >= 444 && py < 460)
                    if (ref8[65*8+(py-444)/2][7-(px-560)/2])
                        expected_rgb = 24'hF0EDE8;
            end
            if (px >= 160 && px < 480 && py >= 168 && py < 312 &&
                !((px < 162 || px >= 478) && (py < 170 || py >= 310))) begin
                if (px == 160 || px == 479 || py == 168 || py == 311)
                    expected_rgb = 24'h878787;
                else begin
                    expected_rgb = 24'h4D4E51;
                    if (px >= 168 && px < 472 && py >= 176 && py < 304) begin
                        bx = (px-168)/2; by = 8+(py-176)/2;
                        line_id = (by-8)/8; slot_id = bx/8;
                        gx = bx%8; gy = (by-8)%8;
                        case (line_id)
                            0: line_text = "     SETTINGS      ";
                            1: line_text = "VOLUME           08";
                            2: line_text = "BRIGHT            2";
                            3: line_text = "CONTRAST          2";
                            4: line_text = "TRANS          FADE";
                            5: line_text = "AUTO             ON";
                            6: line_text = "PERIOD           3S";
                            7: line_text = "INFO             ON";
                        endcase
                        ch = line_text >> ((18-slot_id)*8);
                        if (gy < 7) begin
                            if (gx < 5 && ref5[ch*8+gy][4-gx])
                                expected_rgb = (line_id == selected+1) ? 24'h1A1D23 : 24'hF0EDE8;
                            else if (line_id == selected+1)
                                expected_rgb = 24'hC4A447;
                        end
                    end
                end
            end
        end
    endfunction

    always @(posedge clk) begin
        if (!rst && request_valid && ready) requests = requests + 1;
        if (!rst && wr_en && wr_y >= 80) begin
            failures = failures + 1;
            $display("FAIL out-of-range write y=%0d", wr_y);
        end
    end

    task read_check;
        input integer px;
        input integer py;
        input [1:0] expected;
        begin
            @(negedge clk); rd_en = 1; rd_x = px; rd_y = py;
            @(posedge clk); #1;
            checked = checked + 1;
            if (rd_valid !== 1'b1 || rd_data !== expected) begin
                if (failures < 30)
                    $display("FAIL pixel x=%0d y=%0d expected=%b actual=%b", px, py, expected, rd_data);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        $readmemh("font5x7_data.mem", ref5);
        if ($value$plusargs("SELECTED=%d", selection_arg)) selected = selection_arg;
        $readmemh("font_data.mem", ref8);
        repeat (3) @(negedge clk);
        rst = 0;
        @(negedge clk); vs = 1;
        wait (menu_busy);
        if ($test$plusargs("REDRAW")) begin
            repeat (127) @(negedge clk);
            selected = (selected == 6) ? 0 : selected+1;
            redraw = 1;
            @(negedge clk); redraw = 0;
            wait (menu_busy);
        end
        wait (!menu_busy);
        if ($test$plusargs("REPAINT")) begin
            wait (!render_busy);
            @(negedge clk);
            selected = (selected == 6) ? 0 : selected+1;
            redraw = 1;
            @(negedge clk); redraw = 0;
            wait (menu_busy);
            wait (!menu_busy);
        end
        @(negedge clk); sb_valid = 1;
        wait (ready);
        @(posedge clk);
        @(negedge clk); sb_valid = 0;
        wait (!render_busy);
        repeat (3) @(negedge clk);
        for (r = 0; r < 8; r = r + 1) begin
            case (r)
                0: expected_line = "     SETTINGS      ";
                1: expected_line = "VOLUME           08";
                2: expected_line = "BRIGHT            2";
                3: expected_line = "CONTRAST          2";
                4: expected_line = "TRANS          FADE";
                5: expected_line = "AUTO             ON";
                6: expected_line = "PERIOD           3S";
                7: expected_line = "INFO             ON";
            endcase
            for (slot = 0; slot < 19; slot = slot + 1) begin
                expected_char = expected_line >> ((18-slot)*8);
                for (y = 0; y < 7; y = y + 1) begin
                    for (x = 0; x < 8; x = x + 1) begin
                        expected_pixel = (x < 5 && ref5[expected_char*8+y][4-x]) ?
                                         ((r == selected+1) ? 2'b01 : 2'b10) :
                                         (r == selected + 1) ? 2'b11 : 2'b00;
                        read_check(slot*8+x, 8+r*8+y, expected_pixel);
                    end
                end
            end
        end
        for (y = 0; y < 8; y = y + 1)
            for (x = 0; x < 8; x = x + 1)
                read_check(248+x, 72+y, ref8[65*8+y][7-x] ? 2'b10 : 2'b00);
        if ($test$plusargs("SCREEN")) begin
            @(negedge clk); scan_mode = 1; scan_rgb = 24'h808080;
            repeat (3) @(negedge clk);
            overlay_rst = 0; scan_vs = 1;
            repeat (3) @(negedge clk);
            scan_vs = 0;
            repeat (3) @(negedge clk);
            for (sy = 0; sy < 480; sy = sy+1) begin
                for (sx = 0; sx < 640; sx = sx+1) begin
                    scan_de = 1;
                    @(posedge clk); #1;
                    screen_expected = expected_rgb(sx, sy);
                    screen_checked = screen_checked+1;
                    if (overlay_de !== 1'b1 || overlay_rgb !== screen_expected) begin
                        if (failures < 30)
                            $display("FAIL screen x=%0d y=%0d expected=%h actual=%h", sx, sy, screen_expected, overlay_rgb);
                        failures = failures+1;
                    end
                    @(negedge clk);
                end
                scan_de = 0;
                repeat (4) @(negedge clk);
            end
            $display("Screen checked=%0d", screen_checked);
        end
        $display("RESULT failures=%0d checked=%0d requests=%0d", failures, checked, requests);
        if (failures != 0) $fatal(1, "menu pipeline pixel mismatch");
        $display("PASS tb_menu_pipeline");
        $finish;
    end
    initial begin
        #8000000;
        $fatal(1, "menu pipeline timeout");
    end
    initial begin
        if ($test$plusargs("INTERRUPT")) begin
            wait (renderer.clr_done_o);
            repeat (17) @(negedge clk);
            while (menu_busy || render_busy || requests < 153) begin
                de = 1; vs = 0;
                repeat (50) @(negedge clk);
                de = 0; vs = 1;
                repeat (137) @(negedge clk);
                interrupted = interrupted + 1;
            end
            $display("Interrupted blank windows=%0d", interrupted);
        end
    end
endmodule
