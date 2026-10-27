`timescale 1ns/1ps
// 步骤1 自检测试台：根目录跨 2 簇，含 0xE5/0x0F/占位项，PIC1/2 在簇2、PIC3/4 在簇3
module tb_scanner_root;

    reg clk;
    reg rst_n;
    reg scan_start;

    wire scan_busy;
    wire scan_done;
    wire [7:0] fs_error;
    wire [31:0] partition_lba;
    wire [7:0]  sectors_per_cluster;
    wire [31:0] fat_start_lba;
    wire [31:0] data_start_lba;
    wire [31:0] max_cluster;
    wire [3:0]  resource_valid;
    wire [31:0] resource0_cluster, resource1_cluster, resource2_cluster, resource3_cluster;
    wire [31:0] resource0_size, resource1_size, resource2_size, resource3_size;
    wire        music_valid;
    wire [31:0] music_cluster, music_size;
    wire        track_push;
    wire [3:0]  track_index;
    wire [87:0] track_name;
    wire [31:0] track_cluster, track_size;
    reg  [15:0] track_seen;

    wire        sector_req;
    wire [31:0] sector_lba;
    reg         sector_busy;
    reg         sector_valid;
    reg  [7:0]  sector_byte;
    reg  [8:0]  sector_byte_index;
    reg         sector_done;
    reg  [7:0]  sector_error;

    // 磁盘模型：覆盖 LBA 0..263
    reg [7:0] disk [0:(264*512-1)];

    integer k;
    integer errors;
    reg saw_done;
    integer watchdog;
    integer vcnt;
    integer done_cnt;
    integer bc;

    // ---- 构造辅助 ----
    task setb; input integer sec; input integer off; input [7:0] v;
        begin disk[sec*512+off] = v; end
    endtask
    task set32; input integer sec; input integer off; input [31:0] v;
        begin
            disk[sec*512+off+0] = v[7:0];
            disk[sec*512+off+1] = v[15:8];
            disk[sec*512+off+2] = v[23:16];
            disk[sec*512+off+3] = v[31:24];
        end
    endtask
    task make_dummy; input integer sec; input integer slot;
        integer base; integer i;
        begin
            base = slot*32;
            disk[sec*512+base+0] = "X";
            for (i=1;i<=10;i=i+1) disk[sec*512+base+i] = " ";
            disk[sec*512+base+11] = 8'h20;
        end
    endtask
    task make_pic; input integer sec; input integer slot; input [7:0] num;
                   input [31:0] fcluster; input [31:0] fsize;
        integer base;
        begin
            base = slot*32;
            disk[sec*512+base+0] = "P";
            disk[sec*512+base+1] = "I";
            disk[sec*512+base+2] = "C";
            disk[sec*512+base+3] = num;
            disk[sec*512+base+4] = " ";
            disk[sec*512+base+5] = " ";
            disk[sec*512+base+6] = " ";
            disk[sec*512+base+7] = " ";
            disk[sec*512+base+8] = "B";
            disk[sec*512+base+9] = "M";
            disk[sec*512+base+10]= "P";
            disk[sec*512+base+11]= 8'h20;
            disk[sec*512+base+26]= fcluster[7:0];
            disk[sec*512+base+27]= fcluster[15:8];
            disk[sec*512+base+20]= 8'd0;
            disk[sec*512+base+21]= 8'd0;
            set32(sec, base+28, fsize);
        end
    endtask
    task make_track; input integer sec; input integer slot; input integer num;
                   input [31:0] fcluster; input [31:0] fsize;
        integer base;
        begin
            base = slot*32;
            disk[sec*512+base+0] = "T";
            disk[sec*512+base+1] = "R";
            disk[sec*512+base+2] = "A";
            disk[sec*512+base+3] = "C";
            disk[sec*512+base+4] = "K";
            disk[sec*512+base+5] = "0" + (num/10);
            disk[sec*512+base+6] = "0" + (num%10);
            disk[sec*512+base+7] = " ";
            disk[sec*512+base+8] = "R";
            disk[sec*512+base+9] = "A";
            disk[sec*512+base+10]= "W";
            disk[sec*512+base+11]= 8'h20;
            disk[sec*512+base+26]= fcluster[7:0];
            disk[sec*512+base+27]= fcluster[15:8];
            disk[sec*512+base+20]= fcluster[23:16];
            disk[sec*512+base+21]= fcluster[31:24];
            set32(sec, base+28, fsize);
        end
    endtask
    task make_music; input integer sec; input integer slot;
                   input [31:0] fcluster; input [31:0] fsize;
        integer base;
        begin
            base = slot*32;
            disk[sec*512+base+0] = "M";
            disk[sec*512+base+1] = "U";
            disk[sec*512+base+2] = "S";
            disk[sec*512+base+3] = "I";
            disk[sec*512+base+4] = "C";
            disk[sec*512+base+5] = " ";
            disk[sec*512+base+6] = " ";
            disk[sec*512+base+7] = " ";
            disk[sec*512+base+8] = "W";
            disk[sec*512+base+9] = "A";
            disk[sec*512+base+10]= "V";
            disk[sec*512+base+11]= 8'h20;
            disk[sec*512+base+26]= fcluster[7:0];
            disk[sec*512+base+27]= fcluster[15:8];
            disk[sec*512+base+20]= 8'd0;
            disk[sec*512+base+21]= 8'd0;
            set32(sec, base+28, fsize);
        end
    endtask

    // ---- DUT ----
    fat32_volume_scanner dut (
        .clk(clk), .rst_n(rst_n), .scan_start(scan_start),
        .scan_busy(scan_busy), .scan_done(scan_done), .fs_error(fs_error),
        .partition_lba(partition_lba), .sectors_per_cluster(sectors_per_cluster),
        .fat_start_lba(fat_start_lba), .data_start_lba(data_start_lba),
        .max_cluster(max_cluster), .resource_valid(resource_valid),
        .resource0_cluster(resource0_cluster), .resource1_cluster(resource1_cluster),
        .resource2_cluster(resource2_cluster), .resource3_cluster(resource3_cluster),
        .resource0_size(resource0_size), .resource1_size(resource1_size),
        .resource2_size(resource2_size), .resource3_size(resource3_size),
        .music_valid(music_valid), .music_cluster(music_cluster), .music_size(music_size),
        .track_push(track_push), .track_index(track_index), .track_name(track_name),
        .track_cluster(track_cluster), .track_size(track_size),
        .sector_req(sector_req), .sector_lba(sector_lba),
        .sector_busy(sector_busy), .sector_valid(sector_valid),
        .sector_byte(sector_byte), .sector_byte_index(sector_byte_index),
        .sector_done(sector_done), .sector_error(sector_error)
    );

    // ---- 扇区主模型（显式 FSM）----
    reg [8:0]  m_idx;
    reg [31:0] m_lba;
    reg [1:0]  m_state;
    localparam M_IDLE=2'd0, M_STREAM=2'd1, M_DONE=2'd2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sector_busy <= 1'b0; sector_valid <= 1'b0; sector_done <= 1'b0;
            sector_byte <= 8'd0; sector_byte_index <= 9'd0;
            m_idx <= 9'd0; m_lba <= 32'd0; m_state <= M_IDLE;
        end else begin
            sector_valid <= 1'b0;
            sector_done  <= 1'b0;
            case (m_state)
                M_IDLE: begin
                    sector_busy <= 1'b0;
                    if (sector_req) begin
                        sector_busy <= 1'b1;
                        m_lba <= sector_lba;
                        m_idx <= 9'd0;
                        m_state <= M_STREAM;
                    end
                end
                M_STREAM: begin
                    sector_valid       <= 1'b1;
                    sector_byte        <= disk[m_lba*512 + m_idx];
                    sector_byte_index  <= m_idx;
                    if (m_idx == 9'd511)
                        m_state <= M_DONE;
                    else
                        m_idx <= m_idx + 9'd1;
                end
                M_DONE: begin
                    sector_valid <= 1'b0;
                    sector_done  <= 1'b1;
                    sector_busy  <= 1'b0;
                    m_state      <= M_IDLE;
                end
                default: m_state <= M_IDLE;
            endcase
        end
    end

    // ---- 调试：进入 BPB 校验时 dump 关键字段 ----
    always @(posedge clk) begin
        if (dut.state == dut.ST_BOOT_PARSE) begin
            $display("BPARSE b11=%h b12=%h b13=%h b14=%h b15=%h b16=%h b17=%h b18=%h b22=%h b23=%h",
                dut.sector_buffer[11], dut.sector_buffer[12], dut.sector_buffer[13],
                dut.sector_buffer[14], dut.sector_buffer[15], dut.sector_buffer[16],
                dut.sector_buffer[17], dut.sector_buffer[18], dut.sector_buffer[22], dut.sector_buffer[23]);
            $display("BPARSE tot=%h%h%h%h fatsz=%h%h%h%h root=%h%h%h%h",
                dut.sector_buffer[35],dut.sector_buffer[34],dut.sector_buffer[33],dut.sector_buffer[32],
                dut.sector_buffer[39],dut.sector_buffer[38],dut.sector_buffer[37],dut.sector_buffer[36],
                dut.sector_buffer[47],dut.sector_buffer[46],dut.sector_buffer[45],dut.sector_buffer[44]);
        end
    end

    integer cyc;
    always @(posedge clk) cyc = cyc + 1;
    always @(posedge clk) begin
        if (track_push) begin
            track_seen[track_index] = 1'b1;
            if (track_cluster != (32'd101 + track_index)) begin
                $display("TRACK cluster mismatch idx=%0d got=%0d",track_index,track_cluster);
                errors = errors + 1;
            end
        end
        if (cyc >= 8 && cyc <= 40)
            $display("cyc=%0d req=%b busy=%b valid=%b done=%b m_idx=%0d state=%0d",
                cyc, sector_req, sector_busy, sector_valid, sector_done, m_idx, dut.state);
        if (sector_valid) vcnt = vcnt + 1;
        if (sector_done) done_cnt = done_cnt + 1;
        if (dut.state == dut.ST_READ0_WAIT && dut.sector_done) begin
            $display("R0DONE vcnt=%0d done_cnt=%0d m_lba=%0d b0=%h b450=%h b510=%h b511=%h",
                vcnt, done_cnt, m_lba,
                dut.sector_buffer[0], dut.sector_buffer[450],
                dut.sector_buffer[510], dut.sector_buffer[511]);
        end
    end

    // ---- 时钟 ----
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ---- 激励与检查 ----
    initial begin
        errors = 0;
        vcnt = 0;
        done_cnt = 0;
        bc = 0;
        cyc = 0;
        saw_done = 1'b0;
        track_seen = 16'd0;
        $display("==== tb_scanner_root start ====");

        // 清零磁盘
        for (k=0; k<(264*512); k=k+1) disk[k] = 8'h00;

        // MBR @0
        disk[450] = 8'h0C;
        set32(0, 454, 32'd200);
        disk[510] = 8'h55; disk[511] = 8'hAA;

        // Boot @200
        disk[200*512+11] = 8'h00; disk[200*512+12] = 8'h02; // 512
        disk[200*512+13] = 8'd8;
        disk[200*512+14] = 8'd32; disk[200*512+15] = 8'd0;
        disk[200*512+16] = 8'd1;
        set32(200, 32, 32'd2048);
        set32(200, 36, 32'd16);
        set32(200, 44, 32'd2);
        disk[200*512+510] = 8'h55; disk[200*512+511] = 8'hAA;

        // FAT @232: 2->3, 3->EOC
        set32(232, 8,  32'd3);
        set32(232, 12, 32'h0FFFFFFF);

        // 根簇2 = 扇区248..255
        // 扇区248
        disk[248*512+0] = 8'hE5;                 // slot0 删除
        disk[248*512+32]  = 8'h41;               // slot1 LFN
        disk[248*512+32+11] = 8'h0F;
        for (k=2; k<=14; k=k+1) make_dummy(248, k);
        make_pic(248, 15, "1", 32'd10, 32'd921654);
        // 扇区249
        make_pic(249, 0, "2", 32'd20, 32'd921654);
        for (k=1; k<=15; k=k+1) make_dummy(249, k);
        // 扇区250..255 全占位
        for (k=250; k<=255; k=k+1) begin : fillc2
            integer s; integer sl;
            begin
                s = k;
                for (sl=0; sl<=15; sl=sl+1) make_dummy(s, sl);
            end
        end

        // 根簇3 = 扇区256..
        make_pic(256, 0, "3", 32'd30, 32'd180054);
        make_pic(256, 1, "4", 32'd40, 32'd2880054);
        // MUSIC.WAV 放在 PIC4 之后(slot2)：验证四图找全后仍继续扫到 WAV
        make_music(256, 2, 32'd100, 32'd480000);
        make_track(256, 3, 16, 32'd116, 32'd960000);
        make_track(256, 4, 2, 32'd102, 32'd480002);
        make_track(256, 5, 10, 32'd110, 32'd720000);
        make_track(256, 6, 1, 32'd101, 32'd240000);
        // slot3 起保持 0x00 -> 目录结束

        // 复位
        rst_n = 1'b0; scan_start = 1'b0;
        sector_error = 8'd0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        scan_start = 1'b1;
        @(posedge clk);
        scan_start = 1'b0;

        // 等待完成
        watchdog = 0;
        while (!saw_done && watchdog < 2000000) begin
            @(posedge clk);
            watchdog = watchdog + 1;
            if (scan_done) saw_done = 1'b1;
        end

        if (!saw_done) begin
            $display("FAIL: scan_done timeout");
            errors = errors + 1;
        end else begin
            $display("scan_done reached, fs_error=0x%0h resource_valid=%b", fs_error, resource_valid);
            if (fs_error !== 8'h00) begin $display("FAIL: fs_error=0x%0h", fs_error); errors=errors+1; end
            if (resource_valid !== 4'hf) begin $display("FAIL: resource_valid=%b", resource_valid); errors=errors+1; end
            if (resource0_cluster !== 32'd10) begin $display("FAIL: c0 cluster=%0d", resource0_cluster); errors=errors+1; end
            if (resource1_cluster !== 32'd20) begin $display("FAIL: c1 cluster=%0d", resource1_cluster); errors=errors+1; end
            if (resource2_cluster !== 32'd30) begin $display("FAIL: c2 cluster=%0d", resource2_cluster); errors=errors+1; end
            if (resource3_cluster !== 32'd40) begin $display("FAIL: c3 cluster=%0d", resource3_cluster); errors=errors+1; end
            if (resource0_size !== 32'd921654) begin $display("FAIL: c0 size=%0d", resource0_size); errors=errors+1; end
            if (resource2_size !== 32'd180054) begin $display("FAIL: c2 size=%0d", resource2_size); errors=errors+1; end
            if (resource3_size !== 32'd2880054) begin $display("FAIL: c3 size=%0d", resource3_size); errors=errors+1; end
            if (music_valid !== 1'b1) begin $display("FAIL: music_valid=%b", music_valid); errors=errors+1; end
            if (music_cluster !== 32'd100) begin $display("FAIL: music cluster=%0d", music_cluster); errors=errors+1; end
            if (music_size !== 32'd480000) begin $display("FAIL: music size=%0d", music_size); errors=errors+1; end
            if (track_seen !== 16'h8203) begin $display("FAIL: track_seen=%h", track_seen); errors=errors+1; end
        end

        repeat (10) @(posedge clk);
        if (errors == 0)
            $display("==== tb_scanner_root PASS ====");
        else
            $display("==== tb_scanner_root FAIL, errors=%0d ====", errors);
        $finish;
    end

endmodule
