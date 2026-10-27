`timescale 1ns/1ps
// ?????????????/?/???
// ???????????? FAIL???"????? 0"?????? PASS
module tb_status_clock;
    reg clk = 1'b0, rst = 1'b1, vs = 1'b0;
    reg [3:0]  track_idx  = 4'd0;
    reg [87:0] track_name = 88'd0;
    wire req_valid;
    reg  req_ready;
    wire [6:0] req_ascii;
    wire [7:0] req_x;
    wire [6:0] req_y;
    wire [1:0] req_type;

    integer errs = 0;
    integer i;

    status_bar_render u_dut (
        .clk(clk), .rst(rst), .vs(vs), .track_idx(track_idx),
        .req_valid(req_valid), .req_ascii(req_ascii), .req_x(req_x), .req_y(req_y),
        .req_type(req_type), .req_ready(req_ready)
    );

    always #19.861 clk = ~clk;
    always @(*) req_ready = req_valid;

    task pulse_vs(input integer n);
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) begin
                @(negedge clk) vs = 1'b1;
                @(negedge clk) vs = 1'b0;
            end
        end
    endtask

    task expect_time(input [6:0] eh, input [5:0] em, input [5:0] es, input [8*24-1:0] tag);
        begin
            if (u_dut.hour !== eh || u_dut.minute !== em || u_dut.second !== es) begin
                errs = errs + 1;
                $display("ERR %0s: ?? %0d:%0d:%0d ?? %0d:%0d:%0d",
                         tag, u_dut.hour, u_dut.minute, u_dut.second, eh, em, es);
            end else begin
                $display("  OK %0s: %0d:%0d:%0d", tag, u_dut.hour, u_dut.minute, u_dut.second);
            end
        end
    endtask

    initial begin
        #5000000;
        $display("TIMEOUT errs=%0d", errs);
        $finish;
    end

    initial begin
        repeat (6) @(posedge clk);
        rst <= 1'b0;
        repeat (4) @(posedge clk);
        expect_time(7'd0, 6'd0, 6'd0, "???");

        // 60 ? = 1 ?
        pulse_vs(60);
        repeat (4) @(posedge clk);
        expect_time(7'd0, 6'd0, 6'd1, "60 ???? 1 ?");

        pulse_vs(60);
        repeat (4) @(posedge clk);
        expect_time(7'd0, 6'd0, 6'd2, "120 ???? 2 ?");

        // ? -> ? ??
        u_dut.second = 6'd59;
        u_dut.minute = 6'd5;
        u_dut.hour   = 7'd0;
        pulse_vs(60);
        repeat (4) @(posedge clk);
        expect_time(7'd0, 6'd6, 6'd0, "59 ?????? 6 ? 0 ?");

        // ? -> ? ??
        u_dut.second = 6'd59;
        u_dut.minute = 6'd59;
        u_dut.hour   = 7'd3;
        pulse_vs(60);
        repeat (4) @(posedge clk);
        expect_time(7'd4, 6'd0, 6'd0, "3:59:59 ????? 4 ?");

        // 99 ???
        u_dut.second = 6'd59;
        u_dut.minute = 6'd59;
        u_dut.hour   = 7'd99;
        pulse_vs(60);
        repeat (4) @(posedge clk);
        expect_time(7'd0, 6'd0, 6'd0, "99:59:59 ????? 0");

        if (errs == 0) $display("STATUS_CLOCK_PASS");
        else           $display("STATUS_CLOCK_FAIL errs=%0d", errs);
        $finish;
    end
endmodule
