`timescale 1ns/1ps

module tb_menu_pipeline2;
    reg clk = 0, rst = 1;
    reg minus_short = 0, plus_short = 0, sel_press = 0;
    wire panel_vis, editing, active, redraw, blink;
    wire [2:0] sel_row, m_bright, m_contrast, m_trans;
    wire [3:0] m_volume, m_period;
    wire m_auto, m_info, m_tone;

    wire        rv, ra_ready;
    wire [6:0]  ra_ascii;
    wire [7:0]  ra_x;
    wire [6:0]  ra_y;
    wire [1:0]  ra_type;

    always #20 clk = ~clk;

    menu_controller #(.CLOCK_MHZ(25), .TIMEOUT_MS(15000)) ctl (
        .clk(clk), .rst(rst),
        .minus_short(minus_short), .minus_long(1'b0),
        .plus_short(plus_short), .plus_long(1'b0),
        .sel_press(sel_press),
        .panel_vis(panel_vis), .sel_row(sel_row), .editing(editing), .active(active),
        .o_volume(m_volume), .o_bright(m_bright), .o_contrast(m_contrast),
        .o_trans(m_trans), .o_auto(m_auto), .o_period(m_period),
        .o_info(m_info), .o_tone(m_tone),
        .redraw(redraw), .blink(blink)
    );

    menu_renderer u_rend (
        .clk(clk), .rst(rst), .vis(panel_vis), .sel_row(sel_row),
        .buf_ready(1'b1), .redraw(redraw), .editing(editing), .blink(blink),
        .p_volume(m_volume), .p_bright(m_bright), .p_contrast(m_contrast),
        .p_trans(m_trans), .p_auto(m_auto), .p_period(m_period),
        .p_info(m_info), .p_tone(m_tone),
        .req_valid(rv), .req_ascii(ra_ascii), .req_x(ra_x), .req_y(ra_y),
        .req_type(ra_type), .req_ready(ra_ready)
    );

    assign ra_ready = 1'b1;

    integer errors = 0;
    integer hl_y = -1;
    integer draws = 0;

    always @(posedge clk) begin
        if (rv && ra_type == 2'b11) hl_y <= ra_y;
        if (redraw)
            $display("REDRAW sel_row=%0d param_now=%h param_q=%h", sel_row, ctl.param_now, ctl.param_q);
    end

    task pulse_minus; begin @(posedge clk); minus_short <= 1; @(posedge clk); minus_short <= 0; repeat (400) @(posedge clk); end endtask
    task pulse_sel;   begin @(posedge clk); sel_press <= 1; @(posedge clk); sel_press <= 0; repeat (400) @(posedge clk); end endtask

    task check_hl(input [8*10:1] tag);
        integer want;
        begin
            want = (sel_row + 1) * 8 + 8;
            if (hl_y != want) begin
                $display("FAIL %0s sel_row=%0d hl_y=%0d want=%0d", tag, sel_row, hl_y, want);
                errors = errors + 1;
            end else $display("ok %0s sel_row=%0d hl_y=%0d", tag, sel_row, hl_y);
        end
    endtask

    initial begin
        rst = 1;
        #200 rst = 0;
        repeat (20) @(posedge clk);
        pulse_sel;
        repeat (600) @(posedge clk);
        check_hl("open");
        pulse_minus; check_hl("r1");
        pulse_minus; check_hl("r2");
        pulse_minus; check_hl("r3");
        pulse_minus; check_hl("r4");
        pulse_minus; check_hl("r5");
        pulse_minus; check_hl("r6");
        pulse_minus; check_hl("wrap0");
        pulse_minus; check_hl("r1b");
        if (errors == 0) $display("PASS tb_menu_pipeline2");
        else             $display("FAIL tb_menu_pipeline2 errors=%0d", errors);
        $finish;
    end
endmodule
