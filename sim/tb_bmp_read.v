`timescale 1ns/1ps
//============================================================================
// tb_bmp_read.v
// bmp_read 首次功能测试台（时序二期 C2 前置）
//   构造一张 20x20 / 24bpp 的最小 BMP 放在 3 个假扇区里，
//   驱动 load_start 完成头部解析 + 升采样行扫描，
//   汇总 active_* / 写入像素数 / 像素校验和，作为改动前后的黄金对照。
//
//   目标显示尺寸用 64x48（缩小目标，加快仿真）。
//   期望几何：源 20x20，fit 到 64x48 -> 等比 48x48，offset_x=(64-48)/2=8，offset_y=0
//   期望写入像素数 = 48*48 = 2304
//============================================================================
module tb_bmp_read;

    localparam TGT_W    = 64;
    localparam TGT_H    = 48;
    localparam SRC_W    = 20;
    localparam SRC_H    = 30;
    localparam HDR      = 54;
    localparam STRIDE   = SRC_W * 3;
    localparam IMG_BYTES= STRIDE * SRC_H;
    localparam FILE_SZ  = HDR + IMG_BYTES;
    localparam SECTORS  = 4;

    reg                    clk;
    reg                    rst;
    reg                    sd_init_done;
    reg                    load_start;
    reg  [31:0]            load_sector;
    reg  [31:0]            load_file_size;
    reg                    write_req_ack;

    wire                   ready;
    wire [3:0]             state_code;
    wire [15:0]            active_width, active_height, active_offset_x, active_offset_y;
    wire [20:0]            active_pixel_count;
    wire                   write_req;
    wire                   sd_sec_read;
    wire [31:0]            sd_sec_read_addr;
    wire                   bmp_data_wr_en;
    wire [23:0]            bmp_data;
    wire                   load_error_pulse;
    wire                   load_complete_pulse;

    reg  [7:0]             sd_sec_read_data;
    reg                    sd_sec_read_data_valid;
    reg                    sd_sec_read_end;

    reg  [7:0]             mem_bytes [0:SECTORS*512-1];

    // 扇区模型
    reg [1:0]              m_st;
    reg [31:0]             m_lba;
    reg [9:0]              m_cnt;
    reg [3:0]              dly;

    integer wr_cnt;
    integer x_cnt;
    integer d_cnt;
    integer sum_data;
    integer xor_data;

    // 升采样纵向映射检查：输出行 o 应取源行 floor(o * SRC_H / active_height)
    reg [15:0] map_last_o;
    reg        map_seen [0:1023];
    integer    map_err;
    integer    map_rows;
    integer    exp_src;

    // 逐行校验和：用于判定"哪些输出行被改变"
    integer    row_sum [0:1023];
    integer    row_cnt [0:1023];
    reg [15:0] rs_last_o;
    integer errors = 0;
    integer i, x, y, idx, b;

    always #4 clk = ~clk;

    bmp_read dut (
        .clk                   (clk),
        .rst                   (rst),
        .ready                 (ready),
        .scan_start            (1'b0),
        .scan_start_sector     (32'd0),
        .scan_max_sector       (32'd0),
        .scan_target_count     (3'd0),
        .scan_done             (),
        .scan_found_valid      (),
        .scan_found_sector     (),
        .scan_found_total      (),
        .load_start            (load_start),
        .load_sector           (load_sector),
        .load_file_size        (load_file_size),
        .sd_init_done          (sd_init_done),
        .state_code            (state_code),
        .bmp_width             (TGT_W),
        .bmp_height            (TGT_H),
        .active_width          (active_width),
        .active_height         (active_height),
        .active_offset_x       (active_offset_x),
        .active_offset_y       (active_offset_y),
        .active_pixel_count    (active_pixel_count),
        .write_req             (write_req),
        .write_req_ack         (write_req_ack),
        .sd_sec_read           (sd_sec_read),
        .sd_sec_read_addr      (sd_sec_read_addr),
        .sd_sec_read_data      (sd_sec_read_data),
        .sd_sec_read_data_valid(sd_sec_read_data_valid),
        .sd_sec_read_end       (sd_sec_read_end),
        .sd_sec_read_error     (1'b0),
        .bmp_data_wr_en        (bmp_data_wr_en),
        .bmp_data              (bmp_data),
        .load_error_pulse      (load_error_pulse),
        .load_complete_pulse   (load_complete_pulse)
    );

    // ---- 假扇区响应 ----
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

    // ---- 写请求应答 + 像素统计 ----
    always @(posedge clk) begin
        if (rst) begin
            write_req_ack <= 1'b0;
            wr_cnt   <= 0;
            x_cnt    <= 0;
            d_cnt    <= 0;
            sum_data <= 0;
            xor_data <= 0;
        end else begin
            write_req_ack <= write_req;
            if (bmp_data_wr_en) begin
                wr_cnt <= wr_cnt + 1;
                if ((^bmp_data) === 1'bx) begin
                    x_cnt <= x_cnt + 1;
                end else begin
                    d_cnt    <= d_cnt + 1;
                    sum_data <= sum_data + bmp_data;
                    xor_data <= xor_data ^ bmp_data;
                end
            end
        end
    end

    // 纵向映射检查：每个输出行第一次写入时，比对 up_source_y
    always @(posedge clk) begin
        if (rst) begin
            map_last_o <= 16'hFFFF;
            map_err    <= 0;
            map_rows   <= 0;
        end else if (bmp_data_wr_en) begin
            if (dut.up_out_y !== map_last_o) begin
                map_last_o <= dut.up_out_y;
                map_rows   <= map_rows + 1;
                exp_src     = (dut.up_out_y * SRC_H) / (active_height == 0 ? 1 : active_height);
                if (dut.up_source_y !== exp_src) begin
                    if (map_err < 5)
                        $display("  MAP MISMATCH out_y=%0d src=%0d expect=%0d", dut.up_out_y, dut.up_source_y, exp_src);
                    map_err <= map_err + 1;
                end
            end
        end
    end

    initial begin
        for (i = 0; i < 1024; i = i + 1) begin
            row_sum[i] = 0;
            row_cnt[i] = 0;
            map_seen[i] = 1'b0;
        end
        rs_last_o = 16'hFFFF;
    end

    always @(posedge clk) begin
        if (!rst && bmp_data_wr_en) begin
            row_sum[dut.up_out_y] = row_sum[dut.up_out_y] + bmp_data;
            row_cnt[dut.up_out_y] = row_cnt[dut.up_out_y] + 1;
        end
    end

    initial begin
        // ---- 构造 BMP ----
        for (i = 0; i < SECTORS*512; i = i + 1) mem_bytes[i] = 8'h00;

        mem_bytes[0] = 8'h42; mem_bytes[1] = 8'h4D;              // 'BM'
        // 文件大小 LE
        mem_bytes[2] = FILE_SZ[7:0];   mem_bytes[3] = FILE_SZ[15:8];
        mem_bytes[4] = FILE_SZ[23:16]; mem_bytes[5] = FILE_SZ[31:24];
        // 保留
        for (i = 6; i < 10; i = i + 1) mem_bytes[i] = 8'h00;
        // 数据偏移 = 54
        mem_bytes[10] = 8'd54; mem_bytes[11] = 8'd0; mem_bytes[12] = 8'd0; mem_bytes[13] = 8'd0;
        // DIB 大小 = 40
        mem_bytes[14] = 8'd40; mem_bytes[15] = 8'd0; mem_bytes[16] = 8'd0; mem_bytes[17] = 8'd0;
        // 宽 20（int32 LE）
        mem_bytes[18] = SRC_W[7:0]; mem_bytes[19] = 8'd0; mem_bytes[20] = 8'd0; mem_bytes[21] = 8'd0;
        // 高 20
        mem_bytes[22] = SRC_H[7:0]; mem_bytes[23] = 8'd0; mem_bytes[24] = 8'd0; mem_bytes[25] = 8'd0;
        // planes = 1
        mem_bytes[26] = 8'd1; mem_bytes[27] = 8'd0;
        // bpp = 24
        mem_bytes[28] = 8'd24; mem_bytes[29] = 8'd0;
        // compression = 0
        for (i = 30; i < 34; i = i + 1) mem_bytes[i] = 8'h00;
        // image size = IMG_BYTES
        mem_bytes[34] = IMG_BYTES[7:0]; mem_bytes[35] = IMG_BYTES[15:8];
        mem_bytes[36] = IMG_BYTES[23:16]; mem_bytes[37] = IMG_BYTES[31:24];
        for (i = 38; i < 54; i = i + 1) mem_bytes[i] = 8'h00;

        // 像素数据：BGR，行自下而上
        for (y = 0; y < SRC_H; y = y + 1) begin
            for (x = 0; x < SRC_W; x = x + 1) begin
                idx = HDR + y*STRIDE + x*3;
                mem_bytes[idx + 0] = (x + y) * 7;      // B
                mem_bytes[idx + 1] = y * 13;           // G
                mem_bytes[idx + 2] = x * 11;           // R
            end
        end

        // ---- 激励 ----
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

        // 等完成或出错（轮询，避免依赖 join_any/disable）
        begin : wait_loop
            integer guard;
            guard = 0;
            while (!load_complete_pulse && !load_error_pulse && guard < 400000) begin
                @(posedge clk);
                guard = guard + 1;
            end
            if (guard >= 400000) $display("TIMEOUT: 未在 400000 拍内完成");
        end

        repeat (20) @(posedge clk);

        $display("==== bmp_read RESULT ====");
        $display("  state_code   = %0d", state_code);
        $display("  active_w/h   = %0d / %0d", active_width, active_height);
        $display("  offset_x/y   = %0d / %0d", active_offset_x, active_offset_y);
        $display("  pixel_count  = %0d", active_pixel_count);
        $display("  wr_pixels    = %0d", wr_cnt);
        $display("  map_rows     = %0d (expect %0d)", map_rows, active_height);
        $display("  map_err      = %0d", map_err);

        if (map_rows <= 64) begin
            $display("  ---- per-row sum (out_y : src_y : count : sum) ----");
            for (i = 0; i < map_rows; i = i + 1)
                $display("   row %0d : src %0d : cnt %0d : sum %0d", i, (i * SRC_H) / (active_height == 0 ? 1 : active_height), row_cnt[i], row_sum[i]);
        end
        $display("  defined_px   = %0d", d_cnt);
        $display("  undef_px     = %0d", x_cnt);
        $display("  sum_data     = %0d", sum_data);
        $display("  xor_data     = %0d", xor_data);
        $display("  load_error   = %0d", load_error_pulse);
        $display("  load_complete= %0d", load_complete_pulse);

        if (load_error_pulse) begin $display("  FAIL: 装载报错"); errors = errors + 1; end
        if (active_width  !== TGT_W/2 + 16) begin
            $display("  NOTE: active_width=%0d（期望 48）", active_width);
        end
        if (wr_cnt !== active_width * active_height) begin
            $display("  FAIL: 写入像素数 %0d != active %0d x %0d = %0d", wr_cnt, active_width, active_height, active_width*active_height);
            errors = errors + 1;
        end

        if (errors == 0) $display("==== BMP_READ SMOKE PASS ====");
        else             $display("==== BMP_READ SMOKE FAIL (%0d) ====", errors);
        $finish;
    end

endmodule
