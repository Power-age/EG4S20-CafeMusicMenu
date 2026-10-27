`timescale 1ns/1ps
module tb_waveform_path;
    reg clk;
    reg rst;
    reg sample_valid;
    reg frame_pulse;
    reg video_de;
    reg signed [23:0] sample_left;
    reg signed [23:0] sample_right;
    wire wave_wr_en;
    wire [9:0] wave_wr_addr;
    wire [7:0] wave_wr_data;
    wire block_done;
    wire block_accept;
    wire front_valid;
    wire front_sel;
    reg rd_en;
    reg [9:0] rd_addr;
    wire [7:0] rd_data;
    wire rd_valid;
    integer errors;
    integer i;
    integer cycles;
    reg [7:0] expected;

    waveform_data data_dut (
        .clk(clk), .rst(rst), .sample_valid(sample_valid),
        .frame_pulse(frame_pulse), .block_accept(block_accept),
        .sample_left(sample_left), .sample_right(sample_right),
        .wave_wr_en(wave_wr_en), .wave_wr_addr(wave_wr_addr),
        .wave_wr_data(wave_wr_data), .block_done(block_done)
    );

    waveform_ram ram_dut (
        .clk(clk), .rst(rst), .wr_en(wave_wr_en), .wr_addr(wave_wr_addr),
        .wr_data(wave_wr_data), .block_done(block_done),
        .frame_pulse(frame_pulse), .video_de(video_de),
        .block_accept(block_accept), .front_valid(front_valid),
        .front_sel(front_sel), .rd_en(rd_en), .rd_addr(rd_addr),
        .rd_data(rd_data), .rd_valid(rd_valid)
    );

    always #20 clk = ~clk;

    function [7:0] compress_ref;
        input [22:0] amplitude;
        integer exponent;
        integer divisor;
        integer mantissa;
        integer q;
        integer scaled;
        begin
            if (amplitude == 0) begin
                compress_ref = 0;
            end else begin
                exponent = 0;
                divisor = 1;
                while ((exponent < 22) && (amplitude >= (divisor << 1))) begin
                    exponent = exponent + 1;
                    divisor = divisor << 1;
                end
                mantissa = ((amplitude - divisor) * 8) / divisor;
                q = 1 + exponent * 8 + mantissa;
                scaled = q + (q >> 2) + (q >> 3) + (q >> 6);
                compress_ref = (scaled > 255) ? 8'd255 : scaled[7:0];
            end
        end
    endfunction

    task send_sample;
        input signed [23:0] value;
        begin
            @(negedge clk);
            sample_left = value;
            sample_right = -value;
            sample_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            sample_valid = 1'b0;
        end
    endtask

    task read_check;
        input [9:0] address;
        begin
            @(negedge clk);
            rd_en = 1'b1;
            rd_addr = address;
            @(posedge clk);
            @(negedge clk);
            if (!rd_valid || rd_data !== expected) begin
                $display("FAIL path addr=%0d got=%0d expected=%0d valid=%b", address, rd_data, expected, rd_valid);
                errors = errors + 1;
            end
            rd_en = 1'b0;
            @(posedge clk);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        sample_valid = 1'b0;
        frame_pulse = 1'b0;
        video_de = 1'b0;
        sample_left = 24'sd0;
        sample_right = 24'sd0;
        rd_en = 1'b0;
        rd_addr = 10'd0;
        errors = 0;
        expected = compress_ref(23'd100000);
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        for (i = 0; i < 806; i = i + 1)
            send_sample(24'sd100000);
        @(negedge clk);
        frame_pulse = 1'b1;
        @(posedge clk);
        @(negedge clk);
        frame_pulse = 1'b0;

        cycles = 0;
        while (!front_valid && cycles < 6000) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        if (!front_valid || cycles >= 6000) begin
            $display("FAIL path commit cycles=%0d", cycles);
            errors = errors + 1;
        end

        read_check(10'd0);
        read_check(10'd1);
        read_check(10'd320);
        read_check(10'd638);
        read_check(10'd639);

        if (errors == 0)
            $display("WAVEFORM_PATH PASS");
        else
            $display("WAVEFORM_PATH FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        #100000000;
        $display("WAVEFORM_PATH TIMEOUT");
        $finish;
    end
endmodule
