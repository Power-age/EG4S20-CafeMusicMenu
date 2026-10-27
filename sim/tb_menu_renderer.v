`timescale 1ns/1ps
// 菜单渲染回归：面板打开后参数"持续抖动"（redraw 连发），绘制不应被打断到永远画不完
// 判据：抖动结束后，8 行 x 19 列每个单元格都必须被写过至少一次（不存在半行/缺行）
module tb_menu_renderer;
    reg clk = 1'b0, rst = 1'b1;
    reg vis = 1'b0, buf_ready = 1'b0, redraw = 1'b0, editing = 1'b0, blink = 1'b0;
    reg [2:0] sel_row = 3'd0;
    reg [3:0] p_volume = 4'd0, p_period = 4'd3;
    reg [2:0] p_bright = 3'd4, p_contrast = 3'd2, p_trans = 3'd0;
    reg       p_auto = 1'b0, p_info = 1'b0;

    wire req_valid, req_fill, busy;
    wire [6:0] req_ascii;
    wire [7:0] req_x;
    wire [6:0] req_y;
    wire [1:0] req_type;
    reg  req_ready;

    integer covered [0:7];
    integer i, errs = 0;
    integer r, c;

    menu_renderer u_dut (
        .clk(clk), .rst(rst), .vis(vis), .sel_row(sel_row), .buf_ready(buf_ready),
        .redraw(redraw), .editing(editing), .blink(blink),
        .p_volume(p_volume), .p_bright(p_bright), .p_contrast(p_contrast),
        .p_trans(p_trans), .p_auto(p_auto), .p_period(p_period), .p_info(p_info),
        .req_valid(req_valid), .req_ascii(req_ascii), .req_x(req_x), .req_y(req_y),
        .req_type(req_type), .req_fill(req_fill), .req_ready(req_ready),
        .busy(busy)
    );

    always #19.861 clk = ~clk;
    always @(*) req_ready = req_valid;

    always @(posedge clk) begin
        if (req_valid) begin
            r = (req_y >> 3) - 1;   // req_y = row*8 + 8
            c = req_x[4:0];
            if (r >= 0 && r <= 7 && c >= 0 && c <= 18)
                covered[r] = covered[r] | (1 << c);
        end
    end

    initial begin
        for (i = 0; i < 8; i = i + 1) covered[i] = 0;
    end

    initial begin
        #3000000;
        $display("TIMEOUT");
        $finish;
    end

    initial begin
        repeat (5) @(posedge clk);
        rst <= 1'b0;
        vis <= 1'b1;
        buf_ready <= 1'b1;
        repeat (3) @(posedge clk);

        // 抖动期：每 20 拍一个 redraw，持续 3000 拍
        for (i = 0; i < 150; i = i + 1) begin
            @(posedge clk) redraw <= 1'b1;
            @(posedge clk) redraw <= 1'b0;
            repeat (18) @(posedge clk);
        end

        repeat (3000) @(posedge clk);

        for (i = 0; i < 8; i = i + 1)
            $display("  row %0d cover = %b", i, covered[i]);
        for (i = 0; i < 8; i = i + 1) begin
            if (covered[i] != 19'h7FFFF) begin
                errs = errs + 1;
                $display("ERR row %0d not fully covered (%b)", i, covered[i]);
            end
        end
        if (busy !== 1'b0) begin errs = errs + 1; $display("ERR draw still busy"); end

        if (errs == 0) $display("MENU_REDRAW_PASS");
        else           $display("MENU_REDRAW_FAIL errs=%0d", errs);
        $finish;
    end
endmodule
