`timescale 1ns/1ps
// 直接打印输出字符序列，验证 SRC <W>X<H>
module tb_src_info_probe;
    reg clk = 1'b0, rst = 1'b1;
    reg [1:0] img_idx = 2'd0;
    reg [15:0] src_w = 16'd640, src_h = 16'd480;

    wire req_valid;
    reg  req_ready;
    wire [6:0] req_ascii;
    wire [7:0] req_x;
    wire [6:0] req_y;
    wire [1:0] req_type;
    wire busy;
    integer cnt = 0;
    integer lines_done = 0;

    src_info_render u_dut (
        .clk(clk), .rst(rst), .img_idx(img_idx), .src_w(src_w), .src_h(src_h),
        .req_valid(req_valid), .req_ascii(req_ascii), .req_x(req_x), .req_y(req_y),
        .req_type(req_type), .req_ready(req_ready), .busy(busy)
    );

    always #19.861 clk = ~clk;
    always @(*) req_ready = req_valid;

    // 每个字符被接受时打印
    always @(posedge clk) begin
        if (req_valid) begin
            if (cnt == 0) $write("  line: ");
            $write("%c", req_ascii);
            cnt = cnt + 1;
            if (cnt == 12) begin
                $write("   [y=%0d x=%0d..%0d]\n", req_y, req_x - 11, req_x);
                cnt = 0;
                lines_done = lines_done + 1;
            end
        end
    end

    initial begin
        #1000000;
        $display("lines_done=%0d", lines_done);
        $finish;
    end

    initial begin
        repeat (4) @(posedge clk);
        rst <= 1'b0;

        repeat (400) @(posedge clk);
        src_w <= 16'd1280; src_h <= 16'd720;
        repeat (400) @(posedge clk);
        src_w <= 16'd480; src_h <= 16'd640;
        repeat (400) @(posedge clk);

        if (lines_done >= 3) $display("SRC_INFO_PASS lines=%0d", lines_done);
        else                 $display("SRC_INFO_FAIL lines=%0d", lines_done);
        $finish;
    end
endmodule
