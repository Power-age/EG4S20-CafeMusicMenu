`timescale 1ns/1ps
// 真实时钟比：wr=100MHz(#5)，rd=25MHz(#20)，tick 每 520 rd 周期(~48k)
// 快写慢读、6144 样本(>4096 多次回绕)，逐样本核对顺序
module tb_wav_realclk;
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

    wav_stream_player #(.ADDR_WIDTH(12), .SAMPLES_PER_SECTOR(256)) dut (
        .wr_clk(wr_clk), .wr_rst_n(wr_rst_n),
        .play_enable(play_enable), .total_sectors(total_sectors),
        .chain_req(chain_req), .chain_k(chain_k),
        .chain_data(chain_data), .chain_valid(chain_valid),
        .chain_end(chain_end), .chain_error(chain_error),
        .rd_clk(rd_clk), .rd_rst_n(rd_rst_n),
        .sample_tick(sample_tick), .sample_out(sample_out),
        .sample_valid(sample_valid), .sample_ready(sample_ready),
        .sample_counter(sample_counter), .stream_active(stream_active),
        .stream_end(stream_end), .buffer_low(buffer_low));

    reg [2:0]  cm;
    reg [8:0]  ci;
    reg [31:0] ck;
    reg [31:0] last_k;
    function [7:0] eb;
        input [31:0] c; input [8:0] i;
        reg [31:0] pos, s; reg [15:0] v;
        begin
            pos = c*512 + {23'd0,i}; s = pos>>1; v = s[15:0]^16'h8000;
            eb = pos[0] ? v[15:8] : v[7:0];
        end
    endfunction
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            cm<=0; ci<=0; ck<=0; last_k<=32'hFFFFFFFF;
            chain_data<=0; chain_valid<=0; chain_end<=0; chain_error<=0;
        end else begin
            chain_valid<=0; chain_end<=0; chain_error<=0;
            case (cm)
            3'd0: if (chain_req && chain_k!==last_k) begin ck<=chain_k; ci<=0; cm<=3'd1; end
            3'd1: begin chain_valid<=1; chain_data<=eb(ck,ci);
                       if (ci==9'd511) cm<=3'd2; else ci<=ci+1; end
            3'd2: begin chain_end<=1; last_k<=ck; cm<=3'd0; end
            endcase
        end
    end

    reg [15:0] td;
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin td<=0; sample_tick<=0; end
        else begin sample_tick<=0;
            if (td>=16'd519) begin sample_tick<=1; td<=0; end else td<=td+1; end
    end

    integer errors;
    reg [31:0] expect_s, true_cnt;
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin expect_s<=0; true_cnt<=0; end
        else if (sample_valid) begin
            if (sample_out[15:0]!=16'd0) begin
                if (sample_out[15:0]!==(expect_s[15:0]^16'h8000)) begin
                    if (errors<10) $display("MISMATCH s=%0d got=%h exp=%h",
                                   expect_s,sample_out,expect_s[15:0]^16'h8000);
                    errors=errors+1;
                end
                expect_s<=expect_s+1; true_cnt<=true_cnt+1;
            end
        end
    end

    initial wr_clk=0; always #5 wr_clk=~wr_clk;   // 100MHz
    initial rd_clk=0; always #20 rd_clk=~rd_clk;  // 25MHz

    integer wd;
    initial begin
        errors=0;
        $display("==== tb_wav_realclk start ====");
        total_sectors=32'd24;
        play_enable=1'b0; sample_ready=1'b1;
        wr_rst_n=1'b0; rd_rst_n=1'b0;
        repeat(4) @(posedge wr_clk);
        wr_rst_n=1'b1; rd_rst_n=1'b1;
        repeat(3) @(posedge wr_clk);
        play_enable=1'b1;
        wd=0;
        while ((true_cnt<32'd6144) && wd<50_000_000) begin @(posedge rd_clk); wd=wd+1; end
        wd=0;
        while ((stream_end!==1'b1) && wd<100000) begin @(posedge rd_clk); wd=wd+1; end
        $display("true_cnt=%0d stream_end=%b", true_cnt, stream_end);
        if (true_cnt!==6144) begin $display("FAIL count"); errors=errors+1; end
        if (stream_end!==1)  begin $display("FAIL end"); errors=errors+1; end
        if (errors==0) $display("REALCLK PASS"); else $display("REALCLK FAIL errors=%0d",errors);
        #50 $finish;
    end
endmodule
