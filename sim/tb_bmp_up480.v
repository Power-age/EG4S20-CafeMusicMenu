`timescale 1ns/1ps
//============================================================================
// tb_bmp_up180.v  —— 上采样通路（小图放大）逐像素校验
//
// 目的：复现真实工程里 480x360 -> 640x480 的上采样场景。
//   现有 tb_bmp_read 用 20x30 源（每行 60 字节，不跨扇区），覆盖不到
//   "一行跨 2~4 个扇区 + 起始扇区内偏移非 0" 的情形。
//
// 本 tb 用 180x135 源 -> 240x180 目标（同为 1.333 倍，每行 540 字节，跨 2 扇区），
// 像素值编码坐标：B=x*7, G=y*13, R=x*11（mod 256）。
// 逐像素比对：输出 (ox,oy) 应等于源 (floor(ox*180/240), floor(oy*135/180))。
//============================================================================
module tb_bmp_up480;

    localparam SRC_W = 480;
    localparam SRC_H = 360;
    localparam TGT_W = 640;
    localparam TGT_H = 480;
    localparam HDR   = 54;
    localparam STRIDE = SRC_W * 3;            // 540
    localparam IMG_BYTES = STRIDE * SRC_H;
    localparam FILE_SZ = HDR + IMG_BYTES;
    localparam SECTORS = 1024;

    reg clk, rst, sd_init_done, load_start;
    reg [31:0] load_sector, load_file_size;
    reg write_req_ack;
    reg write_hold;
    reg [7:0] hold_cnt;
    wire ready;
    wire [3:0] state_code;
    wire [15:0] active_width, active_height, active_offset_x, active_offset_y;
    wire [20:0] active_pixel_count;
    wire write_req;
    wire sd_sec_read;
    wire [31:0] sd_sec_read_addr;
    wire bmp_data_wr_en;
    wire [23:0] bmp_data;
    wire load_error_pulse, load_complete_pulse;

    reg [7:0] sd_sec_read_data;
    reg sd_sec_read_data_valid, sd_sec_read_end;
    reg [7:0] mem_bytes [0:SECTORS*512-1];

    reg [1:0] m_st;
    reg [31:0] m_lba;
    reg [9:0] m_cnt;
    reg [3:0] dly;

    integer i, x, y, idx, cnt, ox, oy, ex, ey, err, undef_cnt;
    integer row_wr_cnt, row_done_cnt, max_raw_x;
    reg dbg_done;
    integer dbg_ev;
    integer rowchk = 0;
    integer k, xcnt;
    integer b_exp, g_exp, r_exp;

    always #4 clk = ~clk;

    // 周期性写反压：每 100 拍中拉高 20 拍，模拟 FIFO 满
    always @(posedge clk) begin
        if (rst) begin hold_cnt <= 8'd0; write_hold <= 1'b0; end
        else begin
            hold_cnt <= (hold_cnt == 8'd99) ? 8'd0 : hold_cnt + 8'd1;
            write_hold <= (hold_cnt >= 8'd80);
        end
    end

    bmp_read dut (
        .clk(clk), .rst(rst), .ready(ready),
        .scan_start(1'b0), .scan_start_sector(32'd0), .scan_max_sector(32'd0),
        .scan_target_count(3'd0), .scan_done(), .scan_found_valid(),
        .scan_found_sector(), .scan_found_total(),
        .load_start(load_start), .load_sector(load_sector), .load_file_size(load_file_size),
        .sd_init_done(sd_init_done), .state_code(state_code),
        .bmp_width(TGT_W), .bmp_height(TGT_H),
        .active_width(active_width), .active_height(active_height),
        .active_offset_x(active_offset_x), .active_offset_y(active_offset_y),
        .active_pixel_count(active_pixel_count),
        .write_req(write_req), .write_req_ack(write_req_ack),
        .sd_sec_read(sd_sec_read), .sd_sec_read_addr(sd_sec_read_addr),
        .sd_sec_read_data(sd_sec_read_data), .sd_sec_read_data_valid(sd_sec_read_data_valid),
        .sd_sec_read_end(sd_sec_read_end), .sd_sec_read_error(1'b0),
        .bmp_data_wr_en(bmp_data_wr_en), .bmp_data(bmp_data), .write_hold(write_hold),
        .load_error_pulse(load_error_pulse), .load_complete_pulse(load_complete_pulse)
    );

    // 假扇区
    always @(posedge clk) begin
        if (rst) begin
            m_st <= 2'd0; sd_sec_read_data_valid <= 1'b0; sd_sec_read_end <= 1'b0;
            sd_sec_read_data <= 8'd0; m_lba <= 32'd0; m_cnt <= 10'd0; dly <= 4'd0;
        end else begin
            sd_sec_read_data_valid <= 1'b0;
            sd_sec_read_end        <= 1'b0;
            case (m_st)
                2'd0: if (sd_sec_read) begin m_lba <= sd_sec_read_addr; m_cnt <= 10'd0; dly <= 4'd0; m_st <= 2'd1; end
                2'd1: begin dly <= dly + 4'd1; if (dly == 4'd2) m_st <= 2'd2; end
                2'd2: begin
                    sd_sec_read_data_valid <= 1'b1;
                    sd_sec_read_data       <= mem_bytes[m_lba*512 + m_cnt];
                    if (m_cnt == 10'd511) begin sd_sec_read_end <= 1'b1; m_st <= 2'd3; end
                    m_cnt <= m_cnt + 10'd1;
                end
                2'd3: m_st <= 2'd0;
            endcase
        end
    end

    // 写应答 + 逐像素校验
    always @(posedge clk) begin
        if (rst) begin
            write_req_ack <= 1'b0;
            cnt <= 0; err <= 0; undef_cnt <= 0;
            row_wr_cnt <= 0; row_done_cnt <= 0; max_raw_x <= 0; dbg_done <= 1'b0; dbg_ev <= 0; rowchk <= 0;
        end else begin
            write_req_ack <= write_req;
            if (dut.up_row_wr_en) row_wr_cnt <= row_wr_cnt + 1;
            if (dut.up_row_wr_en && dut.up_out_y == 16'd4 && dut.up_raw_x >= 16'd120 && dut.up_raw_x <= 16'd132)
                $display("  WRDBG out_y=%0d addr=%0d data=%06X bytecnt=%0d idx=%0d pixdata=%04X",
                         dut.up_out_y, dut.up_raw_x, dut.up_row_wr_data,
                         dut.up_row_read_byte_cnt, dut.up_pixel_byte_idx, dut.up_pixel_data);
            if (dut.sd_sec_read_end && dbg_ev < 14) begin
                dbg_ev <= dbg_ev + 1;
                $display("  SECEND lba=%0d start_sector=%0d off=%0d row_bytes=%0d raw_x=%0d out_y=%0d",
                         dut.sd_sec_read_addr, dut.up_row_start_sector, dut.up_sector_start_offset,
                         dut.up_row_read_byte_cnt, dut.up_raw_x, dut.up_out_y);
            end
            if (dut.state == 5'd16 && dbg_done == 0) begin // ST_UP_SCALE
                dbg_done <= 1;
                $display("  DBG first SCALE: mem[0]=%06X mem[1]=%06X mem[179]=%06X stride=%0d raw_x=%0d",
                         dut.up_row_sim_mem[0], dut.up_row_sim_mem[1], dut.up_row_sim_mem[479],
                         dut.source_row_stride, dut.up_raw_x);
            end
            // 每次进入 ST_UP_SCALE 时统计该行 0..179 中有多少 X（行写入完整性）
            if (dut.state == 5'd16 && rowchk < 8) begin
                rowchk <= rowchk + 1;
                xcnt = 0;
                for (k = 0; k < SRC_W; k = k + 1)
                    if ((^dut.up_row_sim_mem[k]) === 1'bx) xcnt = xcnt + 1;
                $display("  ROWCHK out_y=%0d  X_entries=%0d / %0d  raw_x=%0d",
                         dut.up_out_y, xcnt, SRC_W, dut.up_raw_x);
            end
            if (dut.up_row_read_done) row_done_cnt <= row_done_cnt + 1;
            if (dut.up_raw_x > max_raw_x) max_raw_x <= dut.up_raw_x;
            if (bmp_data_wr_en) begin
                ox = cnt % TGT_W;
                oy = cnt / TGT_W;
                ex = (ox * SRC_W) / TGT_W;
                ey = (oy * SRC_H) / TGT_H;
                b_exp = (ex * 7)  & 8'hFF;
                g_exp = (ey * 13) & 8'hFF;
                r_exp = (ex * 11) & 8'hFF;
                if ((^bmp_data) === 1'bx) begin
                    undef_cnt = undef_cnt + 1;
                    if (undef_cnt < 6)
                        $display("  UNDEF out=(%0d,%0d) src_x=%0d src_y=%0d mem@src=%06X rd_en=%b state=%0d",
                                 ox, oy, dut.up_emit_src_x, dut.up_source_y,
                                 dut.up_row_sim_mem[dut.up_emit_src_x], dut.up_row_rd_en, dut.state);
                end else if (bmp_data[7:0] !== b_exp[7:0] ||
                             bmp_data[15:8] !== g_exp[7:0] ||
                             bmp_data[23:16] !== r_exp[7:0]) begin
                    err = err + 1;
                    if (err <= 10)
                        $display("  PIX MISMATCH out=(%0d,%0d) expect src=(%0d,%0d) BGR=%02X%02X%02X expect %02X%02X%02X",
                                 ox, oy, ex, ey, bmp_data[23:16], bmp_data[15:8], bmp_data[7:0],
                                 r_exp[7:0], g_exp[7:0], b_exp[7:0]);
                end
                cnt <= cnt + 1;
            end
        end
    end

    initial begin
        for (i = 0; i < SECTORS*512; i = i + 1) mem_bytes[i] = 8'h00;

        mem_bytes[0] = 8'h42; mem_bytes[1] = 8'h4D;
        mem_bytes[2] = FILE_SZ[7:0];   mem_bytes[3] = FILE_SZ[15:8];
        mem_bytes[4] = FILE_SZ[23:16]; mem_bytes[5] = FILE_SZ[31:24];
        mem_bytes[10] = 8'd54; mem_bytes[11] = 8'd0; mem_bytes[12] = 8'd0; mem_bytes[13] = 8'd0;
        mem_bytes[14] = 8'd40; mem_bytes[15] = 8'd0; mem_bytes[16] = 8'd0; mem_bytes[17] = 8'd0;
        mem_bytes[18] = SRC_W[7:0]; mem_bytes[19] = SRC_W[15:8]; mem_bytes[20] = 8'd0; mem_bytes[21] = 8'd0;
        mem_bytes[22] = SRC_H[7:0]; mem_bytes[23] = SRC_H[15:8]; mem_bytes[24] = 8'd0; mem_bytes[25] = 8'd0;
        mem_bytes[26] = 8'd1; mem_bytes[27] = 8'd0;
        mem_bytes[28] = 8'd24; mem_bytes[29] = 8'd0;
        mem_bytes[34] = IMG_BYTES[7:0]; mem_bytes[35] = IMG_BYTES[15:8];
        mem_bytes[36] = IMG_BYTES[23:16]; mem_bytes[37] = IMG_BYTES[31:24];

        for (y = 0; y < SRC_H; y = y + 1) begin
            for (x = 0; x < SRC_W; x = x + 1) begin
                idx = HDR + y*STRIDE + x*3;
                mem_bytes[idx + 0] = (x * 7)  & 8'hFF;   // B
                mem_bytes[idx + 1] = (y * 13) & 8'hFF;   // G
                mem_bytes[idx + 2] = (x * 11) & 8'hFF;   // R
            end
        end

        clk = 0; rst = 1; sd_init_done = 0; load_start = 0;
        load_sector = 32'd0; load_file_size = FILE_SZ;

        repeat (5) @(posedge clk);
        rst = 0;
        repeat (5) @(posedge clk);
        sd_init_done = 1;
        repeat (3) @(posedge clk);
        load_start = 1;
        repeat (2) @(posedge clk);
        load_start = 0;

        begin : wait_loop
            integer guard;
            guard = 0;
            while (!load_complete_pulse && !load_error_pulse && guard < 2000000) begin
                @(posedge clk);
                guard = guard + 1;
            end
            if (guard >= 2000000) $display("TIMEOUT: 未在 2000000 拍内完成");
        end

        repeat (20) @(posedge clk);

        $display("==== tb_bmp_up480 RESULT ====");
        $display("  active_w/h = %0d / %0d  (expect %0d / %0d)", active_width, active_height, TGT_W, TGT_H);
        $display("  offset_x/y = %0d / %0d", active_offset_x, active_offset_y);
        $display("  wr_pixels  = %0d (expect %0d)", cnt, active_width * active_height);
        $display("  pix_err    = %0d   undef = %0d", err, undef_cnt);
        $display("  row_wr     = %0d (expect %0d)  rows_done = %0d  max_raw_x = %0d (expect %0d)",
                 row_wr_cnt, SRC_W*SRC_H, row_done_cnt, max_raw_x, SRC_W);
        if (load_error_pulse) $display("  FAIL: 装载报错");
        if (err == 0 && undef_cnt == 0 && cnt == active_width * active_height)
            $display("==== tb_bmp_up180 PASS ====");
        else
            $display("==== tb_bmp_up180 FAIL ====");
        $finish;
    end

endmodule
