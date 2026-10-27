`timescale 1ns/1ps
// 字幕回归（滚入后固定）：
//   切图后从 tick=8 逐字符滚入到 tick=0，然后停住不再刷新
module tb_subtitle_ticker;
    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg         vis = 1'b1;
    reg         buf_ready = 1'b0;
    reg         vs = 1'b0;
    reg  [1:0]  img_idx = 2'd0;
    wire        req_valid, req_fill, busy;
    wire [6:0]  req_ascii;
    wire [7:0]  req_x;
    wire [6:0]  req_y;
    wire [1:0]  req_type;
    reg         req_ready;

    reg  [7:0]  txt [0:255];
    integer     errs = 0;
    integer     exp_tick = 32;
    integer     i, b;

    subtitle_render u_dut (
        .clk(clk), .rst(rst), .vis(vis), .buf_ready(buf_ready), .vs(vs),
        .img_idx(img_idx), .req_valid(req_valid), .req_ascii(req_ascii),
        .req_x(req_x), .req_y(req_y), .req_type(req_type), .req_fill(req_fill),
        .req_ready(req_ready), .busy(busy)
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

    task expect_burst(input [1:0] img);
        integer k;
        reg [6:0] exp;
        begin
            while (!busy) @(negedge clk);
            for (k = 0; k < 32; k = k + 1) begin
                while (!req_valid) @(negedge clk);
                exp = txt[img * 64 + exp_tick + k][6:0];
                if (req_ascii !== exp || req_x !== k[7:0] || req_fill !== 1'b0 || req_y !== 7'd0) begin
                    errs = errs + 1;
                    if (errs <= 6)
                        $display("ERR img=%0d tick=%0d pos=%0d ascii=%02h x=%0d y=%0d want %02h",
                                 img, exp_tick, k, req_ascii, req_x, req_y, exp);
                end
                @(negedge clk);
            end
            while (busy) @(negedge clk);
            if (exp_tick > 0) exp_tick = exp_tick - 1;
        end
    endtask

    task expect_fills;
        integer k;
        begin
            while (!busy) @(negedge clk);
            for (k = 0; k < 32; k = k + 1) begin
                while (!req_valid) @(negedge clk);
                if (!req_fill || req_ascii !== 7'd32) begin
                    errs = errs + 1;
                    if (errs <= 6) $display("ERR clear %0d: fill=%0d ascii=%02h", k, req_fill, req_ascii);
                end
                @(negedge clk);
            end
            while (busy) @(negedge clk);
        end
    endtask

    initial begin
        #5000000;
        $display("TIMEOUT errs=%0d", errs);
        $finish;
    end

    initial begin
        $readmemh("ticker_text.mem", txt);
        repeat (5) @(posedge clk);
        rst <= 1'b0;
        repeat (3) @(posedge clk);

        // 1) 首屏：tick 8 -> 0，共 9 次突发
        @(negedge clk) buf_ready <= 1'b1;
        for (b = 0; b < 33; b = b + 1) begin
            expect_burst(2'd0);
            if (b < 32) begin
                for (i = 0; i < 3; i = i + 1) pulse_vs(1);
                pulse_vs(1);
            end
        end
        if (exp_tick !== 0) begin errs = errs + 1; $display("ERR exp_tick 应归 0"); end

        // 2) 滚完应停住：再给 40 帧不应有突发
        pulse_vs(40);
        if (busy) begin errs = errs + 1; $display("ERR 滚完后仍在刷新"); end
        else $display("  OK 滚入结束，文字固定显示");

        // 3) 切图：重新从 tick=8 滚入
        img_idx <= 2'd1;
        exp_tick = 32;
        expect_burst(2'd1);

        // 4) 面板打开清空
        vis <= 1'b0;
        expect_fills;
        if (req_valid) begin errs = errs + 1; $display("ERR 清空后仍有请求"); end

        if (errs == 0) $display("SUBTITLE_SCROLLIN_PASS");
        else           $display("SUBTITLE_SCROLLIN_FAIL errs=%0d", errs);
        $finish;
    end
endmodule
