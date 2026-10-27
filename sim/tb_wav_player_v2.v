`timescale 1ns/1ps
module tb_wav_player_v2;
    reg wr_clk, rd_clk, wr_rst_n, rd_rst_n;
    reg play_start, play_stop;
    reg [31:0] file_size_bytes;
    wire play_busy, source_done, play_finish, play_error;
    wire chain_req;
    wire [31:0] chain_k;
    reg [7:0] chain_data;
    reg chain_valid, chain_end, chain_error;
    reg sample_tick, sample_ready;
    wire signed [15:0] sample_out;
    wire sample_valid;
    wire [31:0] sample_counter;
    wire stream_active, stream_end, buffer_low;
    integer errors;
    integer byte_index;
    integer sector_active;
    reg [31:0] last_k;
    integer samples_seen;
    integer expected_sample;
    integer watchdog;

    wav_stream_player dut (
        .wr_clk(wr_clk),.wr_rst_n(wr_rst_n),.play_start(play_start),.play_stop(play_stop),
        .file_size_bytes(file_size_bytes),.play_busy(play_busy),.source_done(source_done),
        .play_finish(play_finish),.play_error(play_error),.chain_req(chain_req),.chain_k(chain_k),
        .chain_data(chain_data),.chain_valid(chain_valid),.chain_end(chain_end),.chain_error(chain_error),
        .rd_clk(rd_clk),.rd_rst_n(rd_rst_n),.sample_tick(sample_tick),.sample_out(sample_out),
        .sample_valid(sample_valid),.sample_ready(sample_ready),.sample_counter(sample_counter),
        .stream_active(stream_active),.stream_end(stream_end),.buffer_low(buffer_low)
    );

    always #5 wr_clk=~wr_clk;
    always #20 rd_clk=~rd_clk;

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if(!wr_rst_n) begin
            chain_valid<=0; chain_end<=0; chain_error<=0; chain_data<=0;
            byte_index<=0; sector_active<=0; last_k<=32'hffffffff;
        end else begin
            chain_valid<=0; chain_end<=0;
            if(chain_req && !sector_active && chain_k!=last_k) begin byte_index<=0; sector_active<=1; last_k<=chain_k; end
            else if(sector_active) begin
                chain_valid<=1;
                chain_data<=byte_index[7:0];
                if(byte_index==511) begin sector_active<=0; chain_end<=1; end
                else byte_index<=byte_index+1;
            end
        end
    end

    reg [9:0] tick_div;
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if(!rd_rst_n) begin tick_div<=0; sample_tick<=0; end
        else begin
            sample_tick<=0;
            if(tick_div==9) begin tick_div<=0; sample_tick<=1; end
            else tick_div<=tick_div+1;
        end
    end

    function [15:0] expected_word;
        input integer sample_number;
        reg [7:0] low_byte;
        reg [7:0] high_byte;
        begin
            low_byte = sample_number * 2;
            high_byte = sample_number * 2 + 1;
            expected_word = {high_byte,low_byte};
        end
    endfunction

    always @(posedge rd_clk) begin
        if(sample_valid && sample_out!==16'sd0) begin
            if(sample_out[15:0] !== expected_word(expected_sample)) begin
                if(errors<8) $display("FAIL sample n=%0d got=%h",expected_sample,sample_out);
                errors=errors+1;
            end
            expected_sample=expected_sample+1;
            samples_seen=samples_seen+1;
        end
    end

    task reset_all;
        begin
            wr_rst_n=0; rd_rst_n=0; play_start=0; play_stop=0; file_size_bytes=0;
            chain_error=0; sample_ready=1; samples_seen=0; expected_sample=0;
            repeat(5) @(posedge wr_clk); wr_rst_n=1; rd_rst_n=1; repeat(5) @(posedge wr_clk);
        end
    endtask

    task run_size;
        input [31:0] size;
        integer expected_count;
        begin
            expected_count=size/2;
            file_size_bytes=size;
            @(negedge wr_clk); play_start=1; @(posedge wr_clk); @(negedge wr_clk); play_start=0;
            watchdog=0;
            while(!play_finish && watchdog<2000000) begin @(posedge wr_clk); watchdog=watchdog+1; end
            if(!play_finish) begin $display("FAIL finish timeout size=%0d",size); errors=errors+1; end
            repeat(3) @(posedge rd_clk);
            if(samples_seen!=expected_count) begin $display("FAIL size=%0d samples=%0d exp=%0d",size,samples_seen,expected_count); errors=errors+1; end
            repeat(20) @(posedge wr_clk);
        end
    endtask

    initial begin
        wr_clk=0; rd_clk=0; errors=0;
        reset_all;
        run_size(32'd2);
        reset_all;
        run_size(32'd510);
        reset_all;
        run_size(32'd512);
        reset_all;
        run_size(32'd514);
        reset_all;
        run_size(32'd1026);
        reset_all;
        file_size_bytes=32'd4096;
        @(negedge wr_clk); play_start=1; @(posedge wr_clk); @(negedge wr_clk); play_start=0;
        repeat(1000) @(posedge wr_clk);
        @(negedge wr_clk); play_stop=1; @(posedge wr_clk); @(negedge wr_clk); play_stop=0;
        watchdog=0;
        while(play_busy && watchdog<100000) begin @(posedge wr_clk); watchdog=watchdog+1; end
        if(play_busy) begin $display("FAIL stop busy"); errors=errors+1; end
        if(errors==0) $display("WAV_PLAYER_V2 PASS");
        else $display("WAV_PLAYER_V2 FAIL errors=%0d",errors);
        $finish;
    end
    initial begin #200000000; $display("WAV_PLAYER_V2 TIMEOUT"); $finish; end
endmodule
