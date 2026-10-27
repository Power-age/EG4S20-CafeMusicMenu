`timescale 1ns/1ps
module tb_osd_renderer;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1;
    reg vs = 1'b0;
    reg de = 1'b0;

    reg        req_valid = 1'b0;
    reg [6:0]  req_ascii = 7'd0;
    reg [7:0]  req_x = 8'd0;
    reg [3:0]  req_y = 4'd0;
    reg [1:0]  req_type = 2'd0;
    wire       req_ready;

    wire       font_rd_en;
    wire [6:0] font_ascii;
    wire [2:0] font_row;
    wire [7:0] font_rd_data;
    wire       font_rd_valid;

    wire       buf_wr_en;
    wire [7:0] buf_wr_x;
    wire [3:0] buf_wr_y;
    wire [1:0] buf_wr_data;
    reg        dirty_clr = 1'b0;
    wire       busy;
    wire [15:0] dirty_row;

    reg        rd_en = 1'b0;
    reg [7:0]  rd_x = 8'd0;
    reg [3:0]  rd_y = 4'd0;
    wire [1:0] rd_data;
    wire       rd_valid;

    integer failures = 0;
    integer r, c, k;
    integer tstart, tend, cycles;
    integer ready_seen = 0;
    reg [7:0] reference [0:1023];
    reg [1:0] clrval;

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

    osd_renderer dut (
        .clk(clk), .rst(rst), .vs(vs), .de(de),
        .req_valid(req_valid), .req_ascii(req_ascii), .req_x(req_x),
        .req_y(req_y), .req_type(req_type), .req_ready(req_ready),
        .font_rd_en(font_rd_en), .font_ascii(font_ascii), .font_row(font_row),
        .font_rd_data(font_rd_data), .font_rd_valid(font_rd_valid),
        .buf_wr_en(buf_wr_en), .buf_wr_x(buf_wr_x), .buf_wr_y(buf_wr_y),
        .buf_wr_data(buf_wr_data), .dirty_clr(dirty_clr),
        .busy(busy), .dirty_row(dirty_row)
    );

    always @(posedge clk)
        if (req_ready && !rst)
            ready_seen = ready_seen + 1;

    task frame_start;
        begin
            @(negedge clk); de = 1'b0; vs = 1'b0;
            repeat (2) @(negedge clk);
            vs = 1'b1;
            repeat (2) @(negedge clk);
            #1;
        end
    endtask

    task send_char;
        input [6:0] asc;
        input [7:0] cx;
        input [3:0] cy;
        input [1:0] typ;
        begin
            @(negedge clk);
            req_valid = 1'b1; req_ascii = asc; req_x = cx; req_y = cy; req_type = typ;
            #1;
            while (req_ready !== 1'b1) begin
                @(negedge clk);
                #1;
            end
            @(posedge clk);
            @(negedge clk);
            req_valid = 1'b0;
            #1;
        end
    endtask

    task wait_idle;
        begin
            @(posedge clk);
            while (busy === 1'b1) @(posedge clk);
        end
    endtask

    task clr_dirty;
        begin
            @(negedge clk); dirty_clr = 1'b1;
            @(posedge clk); @(negedge clk);
            dirty_clr = 1'b0; #1;
        end
    endtask

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
                        $display("FAIL char asc=%0d x=%0d y=%0d r=%0d c=%0d expect=%b actual=%b",
                                 asc, cx, cy, r, c, expect, val);
                        failures = failures + 1;
                    end
                end
            end
        end
    endtask

    initial begin
        $readmemh("font_data.mem", reference);
        repeat (2) @(negedge clk);
        rst = 1'b0;
        #1;

        frame_start;

        // 用例0：上电一次性清屏，4096 单元抽查应为 0
        repeat (5000) @(posedge clk);
        for (k = 0; k < 16; k = k + 1) begin
            read_pixel(k * 256, clrval);
            if (clrval !== 2'b00) begin
                $display("FAIL clear addr=%0d actual=%b", k * 256, clrval);
                failures = failures + 1;
            end
        end

        // 用例1：单字符 A @ col2,y0 type=10，逐像素核对
        send_char(7'd65, 8'd2, 4'd0, 2'b10);
        wait_idle;
        verify_char(8'd2, 4'd0, 7'd65, 2'b10);
        if (dirty_row[7:0] !== 8'hFF || dirty_row[15:8] !== 8'h00) begin
            $display("FAIL dirty after A row0: %h", dirty_row);
            failures = failures + 1;
        end
        clr_dirty;
        if (dirty_row !== 16'h0000) begin
            $display("FAIL dirty clear: %h", dirty_row);
            failures = failures + 1;
        end

        // 用例2：连续多字符 ANLU @ y8，不丢不重叠
        send_char(7'd65, 8'd0, 4'd8, 2'b10); wait_idle;
        send_char(7'd78, 8'd1, 4'd8, 2'b10); wait_idle;
        send_char(7'd76, 8'd2, 4'd8, 2'b10); wait_idle;
        send_char(7'd85, 8'd3, 4'd8, 2'b10); wait_idle;
        verify_char(8'd0, 4'd8, 7'd65, 2'b10);
        verify_char(8'd1, 4'd8, 7'd78, 2'b10);
        verify_char(8'd2, 4'd8, 7'd76, 2'b10);
        verify_char(8'd3, 4'd8, 7'd85, 2'b10);
        if (dirty_row[15:8] !== 8'hFF || dirty_row[7:0] !== 8'h00) begin
            $display("FAIL dirty after ANLU row8: %h", dirty_row);
            failures = failures + 1;
        end
        clr_dirty;

        // 用例3：活动区拒绝绘制；de 拉低但未重新给 vs 也不绘制；重新 vs 后恢复
        @(negedge clk); de = 1'b1;
        req_valid = 1'b1; req_ascii = 7'd65; req_x = 8'd5; req_y = 4'd0; req_type = 2'b10;
        repeat (60) begin
            @(posedge clk); #1;
            if (buf_wr_en === 1'b1 || font_rd_en === 1'b1) begin
                $display("FAIL render during active de");
                failures = failures + 1;
            end
        end
        @(negedge clk); de = 1'b0;
        repeat (30) begin
            @(posedge clk); #1;
            if (buf_wr_en === 1'b1 || font_rd_en === 1'b1) begin
                $display("FAIL render without new vs");
                failures = failures + 1;
            end
        end
        @(negedge clk); req_valid = 1'b0;
        frame_start;
        send_char(7'd65, 8'd5, 4'd0, 2'b10);
        wait_idle;
        verify_char(8'd5, 4'd0, 7'd65, 2'b10);

        // 用例5：32 字符持续流在一个消隐窗口内全部完成，type=11
        frame_start;
        ready_seen = 0;
        @(negedge clk);
        req_valid = 1'b1; req_y = 4'd0; req_type = 2'b11;
        #1;
        tstart = $time;
        for (k = 0; k < 32; k = k + 1) begin
            req_ascii = 7'd65 + k[6:0];
            req_x = k[7:0];
            #1;
            while (req_ready !== 1'b1) begin
                @(negedge clk);
                #1;
            end
            @(posedge clk);
        end
        @(negedge clk); req_valid = 1'b0;
        @(posedge clk);
        while (busy === 1'b1) @(posedge clk);
        tend = $time;
        cycles = (tend - tstart) / 10;
        for (k = 0; k < 32; k = k + 1)
            verify_char(k[7:0], 4'd0, 7'd65 + k[6:0], 2'b11);
        if (ready_seen !== 32) begin
            $display("FAIL ready count=%0d expected=32", ready_seen);
            failures = failures + 1;
        end
        if (cycles > 2640) begin
            $display("FAIL 32-char budget cycles=%0d", cycles);
            failures = failures + 1;
        end else begin
            $display("INFO 32-char rendered in %0d cycles, ready=%0d", cycles, ready_seen);
        end

        @(negedge clk);
        rst = 1'b1;
        #1;
        if (busy !== 1'b0 || dirty_row !== 16'h0000) begin
            $display("FAIL reset state busy=%b dirty=%h", busy, dirty_row);
            failures = failures + 1;
        end

        if (failures == 0) $display("PASS tb_osd_renderer");
        else $fatal(1, "tb_osd_renderer failures=%0d", failures);
        $finish;
    end
endmodule
