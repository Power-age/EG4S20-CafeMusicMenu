`timescale 1ns/1ps
// =====================================================================
//  video_zoom 1.5x 映射验证
//  喂入"源像素坐标编码"的流：第 r 行第 c 列像素编码为 (r*1000+c)，
//  输出端解码，检查 (x,y) 是否等于期望的 (row0 + 2y/3 - 1, col0 + 2x/3)。
// =====================================================================
module tb_zoom;

    reg clk = 0, rst = 1;
    reg zoom_en = 1;
    reg [9:0] col0 = 10'd100, row0 = 10'd50;
    reg de = 0, vs = 0;
    reg [31:0] fifo_data = 0;
    wire z_pop;
    wire [23:0] z_data;

    always #5 clk = ~clk;

    video_zoom dut (
        .clk(clk), .rst(rst), .zoom_en(zoom_en),
        .col0(col0), .de(de), .vs(vs),
        .fifo_data(fifo_data), .z_pop(z_pop), .z_data(z_data)
    );

    // ---- 源流发生器：raster 顺序，640 宽 ----
    integer src_r = 0, src_c = 0;
    reg [23:0] coded;
    always @(*) begin
        coded     = (row0 + src_r) * 1000 + src_c;
        fifo_data = {coded, 8'h00};   // 真实流约定：像素在 [31:8]
    end

    always @(posedge clk) begin
        if (z_pop) begin
            if (src_c == 639) begin
                src_c <= 0;
                src_r <= src_r + 1;
            end else begin
                src_c <= src_c + 1;
            end
        end
    end



    // ---- 探针 ----
    integer npop = 0, nwr = 0, nrd_nz = 0;
    reg first_wr = 1'b1, first_nz = 1'b1;
    always @(posedge clk) begin
        if (dut.yc == 5 && dut.xc == 5)
            $display("PROBE y=5: mem[0]=%0d mem[512]=%0d rd_addr=%0d src_y=%0d src_x=%0d wr_bank=%0d rd_bank=%0d",
                     dut.sim_mem[0], dut.sim_mem[512], dut.rd_addr, dut.src_y, dut.src_x, dut.wr_bank, dut.rd_bank);
        if (dut.z_pop) npop = npop + 1;
        if (dut.wr_en) begin
            nwr = nwr + 1;
            if (first_wr) begin
                $display("FIRST WRITE addr=%0d data=%0d (bank %0d pcnt %0d) at y=%0d",
                         dut.wr_addr, dut.fifo_data[23:0], dut.wr_bank, dut.pcnt, dut.yc);
                first_wr = 1'b0;
            end
        end
        if (dut.zoom_en && dut.de && (dut.z_data != 24'd0) && first_nz) begin
            $display("FIRST NONZERO OUT y=%0d x=%0d val=%0d", dut.yc, dut.xc, dut.z_data);
            first_nz = 1'b0;
        end
    end
    // ---- 输出检查 ----
    integer ox, oy, errors = 0, checks = 0;
    integer exp_r, exp_c, got_r, got_c;

    // 延迟一拍：z_data 相对地址晚一拍（BRAM 同步读）
    reg de_q; reg [9:0] x_q, y_q;
    always @(posedge clk or posedge rst) begin
        if (rst) begin de_q <= 1'b0; x_q <= 10'd0; y_q <= 10'd0; end
        else begin de_q <= de; x_q <= dut.xc; y_q <= dut.yc; end
    end

    always @(posedge clk) begin
        if (!rst) begin
            if (de_q && (y_q > 10'd4) && (x_q > 10'd2)) begin
                oy = y_q;
                ox = x_q;
                exp_r = row0 + (2 * oy) / 3 - 1;
                exp_c = col0 + (2 * ox) / 3;
                checks = checks + 1;
                got_r = z_data / 1000;
                got_c = z_data % 1000;
                if ((got_r != exp_r) || (got_c != exp_c)) begin
                    if (errors < 10)
                        $display("MISMATCH out(%0d,%0d): got(row %0d,col %0d) expect(row %0d,col %0d)",
                                 ox, oy, got_r, got_c, exp_r, exp_c);
                    errors = errors + 1;
                end
            end
        end
    end

    // ---- 扫描时序 ----
    integer y, x;
    initial begin
        rst = 1;
        repeat (10) @(posedge clk);
        rst = 0;
        for (y = 0; y < 480; y = y + 1) begin
            vs = (y == 0);
            de = 0;
            repeat (20) @(posedge clk);
            for (x = 0; x < 640; x = x + 1) begin
                de = 1;
                @(posedge clk);
            end
        end
        $display("SIM DONE: checks=%0d errors=%0d pops=%0d writes=%0d", checks, errors, npop, nwr);
        $finish;
    end

endmodule
