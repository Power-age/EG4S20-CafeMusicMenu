`timescale 1ns/1ps
// wav_stream_player 单元测试
// 场景1：chain 连续返回 24 扇区（6144 样本，>4096 覆盖缓冲回绕），样本顺序/组装正确，播完 stream_end
// 场景2：消费极快、chain 很慢 -> 下溢输出静音但 sample_valid 不断
module tb_wav_player;
    reg wr_clk, rd_clk;
    reg wr_rst_n, rd_rst_n;
    reg play_enable;
    reg [31:0] total_sectors;
    reg        sample_tick;

    wire        chain_req;
    wire [31:0] chain_k;
    reg  [7:0]  chain_data;
    reg         chain_valid, chain_end, chain_error;

    wire signed [15:0] sample_out;
    wire        sample_valid;
    reg         sample_ready;
    wire [31:0] sample_counter;
    wire        stream_active, stream_end, buffer_low;

    wav_stream_player #(
        .ADDR_WIDTH(12), .SAMPLES_PER_SECTOR(256)
    ) dut (
        .wr_clk(wr_clk), .wr_rst_n(wr_rst_n),
        .play_enable(play_enable), .total_sectors(total_sectors),
        .chain_req(chain_req), .chain_k(chain_k),
        .chain_data(chain_data), .chain_valid(chain_valid),
        .chain_end(chain_end), .chain_error(chain_error),
        .rd_clk(rd_clk), .rd_rst_n(rd_rst_n),
        .sample_tick(sample_tick), .sample_out(sample_out),
        .sample_valid(sample_valid), .sample_ready(sample_ready),
        .sample_counter(sample_counter), .stream_active(stream_active),
        .stream_end(stream_end), .buffer_low(buffer_low)
    );

    // ---- chain bmp 侧模型 ----
    reg [2:0]  cm;
    reg [8:0]  ci;
    reg [31:0] ck;
    reg [31:0] last_k;
    reg [15:0] dly;
    reg        slow;

    // 文件字节位置 -> 期望字节；样本 s 的值 = s ^ 0x8000（s=0..6143 内不会为 0）
    function [7:0] eb;
        input [31:0] c;
        input [8:0]  i;
        reg [31:0] pos, s;
        reg [15:0] v;
        begin
            pos = c*512 + {23'd0, i};
            s   = pos >> 1;
            v   = s[15:0] ^ 16'h8000;
            eb  = pos[0] ? v[15:8] : v[7:0];
        end
    endfunction

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            cm<=3'd0; ci<=9'd0; ck<=32'd0; last_k<=32'hFFFFFFFF; dly<=16'd0;
            chain_data<=8'd0; chain_valid<=1'b0;
            chain_end<=1'b0; chain_error<=1'b0;
        end else begin
            chain_valid<=1'b0; chain_end<=1'b0; chain_error<=1'b0;
            case (cm)
            3'd0: if (chain_req && chain_k!==last_k) begin
                      ck<=chain_k; ci<=9'd0; dly<=16'd0;
                      cm<= slow ? 3'd3 : 3'd1;
                  end
            2'd3: if (dly>=16'd300) cm<=2'd1;
                  else dly<=dly+16'd1;
            2'd1: begin
                      chain_valid<=1'b1;
                      chain_data <=eb(ck, ci);
                      if (ci==9'd511) cm<=2'd2;
                      else ci<=ci+9'd1;
                  end
            3'd2: begin chain_end<=1'b1; last_k<=ck; cm<=3'd0; end
            endcase
        end
    end

    // ---- 读侧 tick 产生 ----
    reg [15:0] td, tperiod;
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin td<=16'd0; sample_tick<=1'b0; end
        else begin
            sample_tick<=1'b0;
            if (td>=tperiod-16'd1) begin sample_tick<=1'b1; td<=16'd0; end
            else td<=td+16'd1;
        end
    end

    // ---- 检查：真样本顺序 ----
    integer errors;
    reg        check_en;
    reg [31:0] expect_s;
    reg [31:0] true_cnt;
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin expect_s<=32'd0; true_cnt<=32'd0; end
        else if (sample_valid && check_en) begin
            if (sample_out[15:0]==16'd0) begin
                // 静音（预填/下溢），不推进
            end else begin
                if (sample_out[15:0] !== (expect_s[15:0] ^ 16'h8000)) begin
                    if (errors<8)
                        $display("SMP MISMATCH s=%0d got=%h exp=%h",
                                 expect_s, sample_out, expect_s[15:0]^16'h8000);
                    errors=errors+1;
                end
                expect_s<=expect_s+32'd1;
                true_cnt<=true_cnt+32'd1;
            end
        end
    end

    // ---- 场景2：统计 tick vs valid，观察静音 ----
    reg [31:0] tick_cnt, valid_cnt;
    reg        saw_silence;
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            tick_cnt<=32'd0; valid_cnt<=32'd0; saw_silence<=1'b0;
        end else begin
            if (sample_tick) tick_cnt<=tick_cnt+32'd1;
            if (sample_valid) begin
                valid_cnt<=valid_cnt+32'd1;
                if (sample_out[15:0]==16'd0) saw_silence<=1'b1;
            end
        end
    end

    initial wr_clk=1'b0; always #5 wr_clk=~wr_clk;
    initial rd_clk=1'b0; always #5 rd_clk=~rd_clk;

    task do_reset;
        begin
            play_enable=1'b0; sample_ready=1'b1;
            wr_rst_n=1'b0; rd_rst_n=1'b0;
            repeat(4) @(posedge wr_clk);
            wr_rst_n=1'b1; rd_rst_n=1'b1;
            repeat(3) @(posedge wr_clk);
        end
    endtask

    integer wd;
    initial begin
        errors=0;
        $display("==== tb_wav_player start ====");

        // ---------- 场景1：连续 24 扇区，6144 样本，覆盖回绕 ----------
        slow=1'b0; tperiod=16'd20; total_sectors=32'd24;
        do_reset;
        check_en=1'b1;
        play_enable=1'b1;
        wd=0;
        while ((true_cnt<32'd6144) && wd<2_000_000) begin
            @(posedge rd_clk); wd=wd+1;
        end
        // 等待写侧 stream_end
        wd=0;
        while ((stream_end!==1'b1) && wd<100000) begin
            @(posedge rd_clk); wd=wd+1;
        end
        $display("[1] true_cnt=%0d sample_counter=%0d stream_end=%b",
                 true_cnt, sample_counter, stream_end);
        if (true_cnt!==32'd6144) begin $display("[1] FAIL true_cnt"); errors=errors+1; end
        if (stream_end!==1'b1)   begin $display("[1] FAIL stream_end"); errors=errors+1; end
        play_enable=1'b0;
        repeat(10) @(posedge wr_clk);
        if (errors==0) $display("[1] SCENARIO-1 PASS");
        else $display("[1] SCENARIO-1 FAIL errors=%0d", errors);

        // ---------- 场景2：下溢静音、valid 不断 ----------
        errors=0;
        slow=1'b1; tperiod=16'd1; total_sectors=32'd1000;
        do_reset;
        check_en=1'b0;
        play_enable=1'b1;
        repeat(20000) @(posedge rd_clk);
        play_enable=1'b0;
        $display("[2] tick=%0d valid=%0d saw_silence=%b",
                 tick_cnt, valid_cnt, saw_silence);
        if (!saw_silence) begin $display("[2] FAIL no silence"); errors=errors+1; end
        // 每个 tick 都应有 valid 响应（仅启动阶段差 1~2）
        if ((tick_cnt - valid_cnt) > 32'd2) begin
            $display("[2] FAIL valid gap tick=%0d valid=%0d", tick_cnt, valid_cnt);
            errors=errors+1;
        end
        if (errors==0) $display("[2] SCENARIO-2 PASS");
        else $display("[2] SCENARIO-2 FAIL errors=%0d", errors);

        $display("==== tb_wav_player done ====");
        #50 $finish;
    end
endmodule
