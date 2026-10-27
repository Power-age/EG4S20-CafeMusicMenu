`timescale 1ns/1ps
module tb_waveform_peak_ram;
    reg clk;
    reg rst;
    reg rd_en;
    reg [9:0] rd_addr;
    wire [5:0] rd_data;
    wire rd_valid;
    reg wr_en;
    reg [9:0] wr_addr;
    reg [5:0] wr_data;
    integer errors;

    waveform_peak_ram dut (
        .clk(clk),
        .rst(rst),
        .rd_en(rd_en),
        .rd_addr(rd_addr),
        .rd_data(rd_data),
        .rd_valid(rd_valid),
        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_data(wr_data)
    );

    always #20 clk = ~clk;

    task write_value;
        input [9:0] address;
        input [5:0] value;
        begin
            @(negedge clk);
            wr_en = 1'b1;
            wr_addr = address;
            wr_data = value;
            @(posedge clk);
            @(negedge clk);
            wr_en = 1'b0;
        end
    endtask

    task read_value;
        input [9:0] address;
        input [5:0] expected;
        begin
            @(negedge clk);
            rd_en = 1'b1;
            rd_addr = address;
            @(posedge clk);
            @(negedge clk);
            if (rd_valid !== 1'b1 || rd_data !== expected) begin
                $display("FAIL peak read addr=%0d valid=%b data=%0d expected=%0d", address, rd_valid, rd_data, expected);
                errors = errors + 1;
            end
            rd_en = 1'b0;
            @(posedge clk);
            @(negedge clk);
            if (rd_valid !== 1'b0) begin
                $display("FAIL peak rd_valid clear addr=%0d", address);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        rd_en = 1'b0;
        rd_addr = 10'd0;
        wr_en = 1'b0;
        wr_addr = 10'd0;
        wr_data = 6'd0;
        errors = 0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        write_value(10'd0, 6'd7);
        write_value(10'd1, 6'd19);
        write_value(10'd639, 6'd48);
        read_value(10'd0, 6'd7);
        read_value(10'd1, 6'd19);
        read_value(10'd639, 6'd48);
        write_value(10'd1, 6'd3);
        read_value(10'd1, 6'd3);
        read_value(10'd0, 6'd7);
        read_value(10'd639, 6'd48);

        if (errors == 0)
            $display("WAVEFORM_PEAK_RAM PASS");
        else
            $display("WAVEFORM_PEAK_RAM FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        #1000000;
        $display("WAVEFORM_PEAK_RAM TIMEOUT");
        $finish;
    end
endmodule
