`timescale 1ns/1ps
module tb_waveform_data;
    reg clk;
    reg rst;
    reg sample_valid;
    reg frame_pulse;
    reg block_accept;
    reg signed [23:0] sample_left;
    reg signed [23:0] sample_right;
    wire wave_wr_en;
    wire [9:0] wave_wr_addr;
    wire [7:0] wave_wr_data;
    wire block_done;
    integer errors;
    integer write_count;
    integer done_count;
    integer expected_addr;
    integer i;

    waveform_data dut (
        .clk(clk), .rst(rst), .sample_valid(sample_valid),
        .frame_pulse(frame_pulse), .block_accept(block_accept),
        .sample_left(sample_left), .sample_right(sample_right),
        .wave_wr_en(wave_wr_en), .wave_wr_addr(wave_wr_addr),
        .wave_wr_data(wave_wr_data), .block_done(block_done)
    );

    always #20 clk = ~clk;

    always @(posedge clk) begin
        if (!rst) begin
            if (wave_wr_en) begin
                if (wave_wr_addr !== expected_addr[9:0]) begin
                    $display("FAIL data addr=%0d expected=%0d", wave_wr_addr, expected_addr);
                    errors = errors + 1;
                end
                expected_addr = expected_addr + 1;
                write_count = write_count + 1;
            end
            if (block_done)
                done_count = done_count + 1;
        end
    end

    task reset_dut;
        begin
            rst = 1'b1;
            sample_valid = 1'b0;
            frame_pulse = 1'b0;
            block_accept = 1'b1;
            sample_left = 24'sd0;
            sample_right = 24'sd0;
            repeat (3) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;
            write_count = 0;
            done_count = 0;
            expected_addr = 0;
        end
    endtask

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

    task close_frame;
        begin
            @(negedge clk);
            frame_pulse = 1'b1;
            @(posedge clk);
            @(negedge clk);
            frame_pulse = 1'b0;
            wait (block_done === 1'b1);
            @(posedge clk);
        end
    endtask

    task run_window;
        input integer samples;
        input integer base;
        begin
            for (i = 0; i < samples; i = i + 1)
                send_sample(base + i);
            close_frame;
            if (write_count != 640 || done_count != 1) begin
                $display("FAIL window samples=%0d writes=%0d done=%0d", samples, write_count, done_count);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        errors = 0;
        reset_dut;
        run_window(800, 1);
        block_accept = 1'b0;
        repeat (10) @(posedge clk);
        if (wave_wr_en || block_done) begin
            $display("FAIL wait activity");
            errors = errors + 1;
        end
        block_accept = 1'b1;
        repeat (2) @(posedge clk);

        reset_dut;
        run_window(806, 1000);
        block_accept = 1'b0;
        repeat (2) @(posedge clk);
        block_accept = 1'b1;
        repeat (2) @(posedge clk);
        write_count = 0;
        done_count = 0;
        expected_addr = 0;
        run_window(807, 2000);

        reset_dut;
        close_frame;
        if (write_count != 640 || done_count != 1) begin
            $display("FAIL zero frame writes=%0d done=%0d", write_count, done_count);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("WAVEFORM_DATA PASS");
        else
            $display("WAVEFORM_DATA FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        #100000000;
        $display("WAVEFORM_DATA TIMEOUT");
        $finish;
    end
endmodule
