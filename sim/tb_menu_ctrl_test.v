`timescale 1ns/1ps

module tb_menu_ctrl_test;
    reg clk = 0, rst = 1;
    reg minus_short = 0, plus_short = 0, sel_press = 0;
    wire panel_vis, editing, active, redraw, blink;
    wire [2:0] sel_row;
    wire [3:0] m_volume, m_period;
    wire [2:0] m_bright, m_contrast, m_trans;
    wire m_auto, m_info, m_tone;

    always #20 clk = ~clk;

    menu_controller #(.CLOCK_MHZ(25), .TIMEOUT_MS(15000)) dut (
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

    task pulse_minus; begin @(posedge clk); minus_short <= 1; @(posedge clk); minus_short <= 0; repeat (5) @(posedge clk); end endtask
    task pulse_plus;  begin @(posedge clk); plus_short  <= 1; @(posedge clk); plus_short  <= 0; repeat (5) @(posedge clk); end endtask
    task pulse_sel;   begin @(posedge clk); sel_press   <= 1; @(posedge clk); sel_press   <= 0; repeat (20) @(posedge clk); end endtask

    integer errors = 0;
    task check_row(input [8*8:1] tag, input [2:0] want);
        begin
            if (sel_row !== want) begin
                $display("FAIL %0s sel_row=%0d want=%0d", tag, sel_row, want);
                errors = errors + 1;
            end else $display("ok %0s sel_row=%0d", tag, sel_row);
        end
    endtask

    initial begin
        rst = 1;
        #200 rst = 0;
        repeat (10) @(posedge clk);
        pulse_sel;               // open panel
        if (!panel_vis) begin $display("FAIL panel not visible"); errors = errors + 1; end
        check_row("after_open", 3'd0);
        pulse_minus; check_row("minus1", 3'd1);
        pulse_minus; check_row("minus2", 3'd2);
        pulse_minus; check_row("minus3", 3'd3);
        pulse_minus; check_row("minus4", 3'd4);
        pulse_minus; check_row("minus5", 3'd5);
        pulse_minus; check_row("minus6", 3'd6);
        pulse_minus; check_row("wrap", 3'd0);
        pulse_plus;  check_row("plus_wrap", 3'd6);
        if (errors == 0) $display("PASS tb_menu_ctrl_test");
        else             $display("FAIL tb_menu_ctrl_test errors=%0d", errors);
        $finish;
    end
endmodule
