`timescale 1ns/1ps
module tb_menu_window;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1;
    reg sel_press = 0;
    integer singles = 0;
    integer doubles = 0;
    integer failures = 0;
    menu_controller #(.CLOCK_MHZ(1), .TIMEOUT_MS(1000)) dut (
        .clk(clk), .rst(rst), .minus_short(1'b0), .minus_long(1'b0),
        .plus_short(1'b0), .plus_long(1'b0), .sel_press(sel_press),
        .panel_vis(), .sel_row(), .editing(), .active(), .o_volume(),
        .o_bright(), .o_contrast(), .o_trans(), .o_auto(), .o_period(),
        .o_info(), .redraw()
    );
    always @(negedge clk) begin
        if (dut.sel_single) singles = singles + 1;
        if (dut.sel_double) doubles = doubles + 1;
    end
    task run_gap;
        input integer gap;
        input integer expected_singles;
        input integer expected_doubles;
        begin
            @(negedge clk); rst = 1; sel_press = 0;
            repeat (4) @(negedge clk);
            rst = 0;
            singles = 0;
            doubles = 0;
            @(negedge clk); sel_press = 1;
            @(negedge clk); sel_press = 0;
            repeat (gap-1) @(negedge clk);
            sel_press = 1;
            @(negedge clk); sel_press = 0;
            repeat (300005) @(negedge clk);
            if (singles != expected_singles || doubles != expected_doubles) begin
                $display("FAIL gap=%0d singles=%0d doubles=%0d expected=%0d/%0d", gap, singles, doubles, expected_singles, expected_doubles);
                failures = failures + 1;
            end
        end
    endtask
    initial begin
        run_gap(299999, 0, 1);
        run_gap(300000, 1, 0);
        run_gap(300001, 2, 0);
        if (failures != 0) $fatal(1, "window failures=%0d", failures);
        $display("PASS tb_menu_window failures=0");
        $finish;
    end
    initial begin #30000000; $fatal(1, "window timeout"); end
endmodule
