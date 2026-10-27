`timescale 1ns/1ps
// 左上角信息条回归：分辨率十进制拆位 + 字符序列
// 注：每次切换后从复位/切换时刻就开始捕获，避免错过首轮突发
module tb_src_info;
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

    reg [7:0] got [0:31];
    integer n, errs = 0;
    reg [8*12-1:0] expect_str;
    reg [11:0] line_done;      // 每字符一位，收满 12 个即完成

    src_info_render u_dut (
        .clk(clk), .rst(rst), .img_idx(img_idx), .src_w(src_w), .src_h(src_h),
        .req_valid(req_valid), .req_ascii(req_ascii), .req_x(req_x), .req_y(req_y),
        .req_type(req_type), .req_ready(req_ready), .busy(busy)
    );

    always #19.861 clk = ~clk;
    always @(*) req_ready = req_valid;

    always @(posedge clk) begin
        if (req_valid) begin
            got[req_x] = {1'b0, req_ascii};
            line_done[req_x - 8'd20] = 1'b1;
        end
    end

    task wait_line;
        begin
            n = 0;
            while (line_done !== 12'hFFF && n < 20000) begin
                @(posedge clk) n = n + 1;
            end
            repeat (4) @(posedge clk);
        end
    endtask

    task check_line(input [8*16-1:0] tag);
        integer m;
        begin
            $write("  %0s: ", tag);
            for (m = 0; m < 12; m = m + 1) $write("%c", got[m + 20]);
            $write("\n");
            for (m = 0; m < 12; m = m + 1)
                if (got[m + 20] !== expect_str[95 - 8*m -: 8]) begin
                    errs = errs + 1;
                    $display("ERR pos %0d: got %02h want %02h", m, got[m + 20], expect_str[95 - 8*m -: 8]);
                end
        end
    endtask

    initial begin
        #3000000;
        $display("TIMEOUT");
        $finish;
    end

    initial begin
        line_done = 12'd0;
        repeat (6) @(posedge clk);
        rst <= 1'b0;

        expect_str = "SRC 640X480";
        wait_line;
        check_line("640x480");

        line_done = 12'd0;
        src_w <= 16'd1280; src_h <= 16'd720;
        expect_str = "SRC 1280X720";
        wait_line;
        check_line("1280x720");

        line_done = 12'd0;
        src_w <= 16'd800; src_h <= 16'd600;
        expect_str = "SRC 800X600";
        wait_line;
        check_line("800x600");

        if (errs == 0) $display("SRC_INFO_PASS");
        else           $display("SRC_INFO_FAIL errs=%0d", errs);
        $finish;
    end
endmodule
