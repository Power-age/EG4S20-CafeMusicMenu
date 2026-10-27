`timescale 1ns/1ps
module tb_osd_buffer;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1;
    reg wr_en = 1'b0;
    reg [7:0] wr_x = 8'd0;
    reg [3:0] wr_y = 4'd0;
    reg [1:0] wr_data = 2'd0;
    reg rd_en = 1'b0;
    reg [7:0] rd_x = 8'd0;
    reg [3:0] rd_y = 4'd0;
    wire [1:0] rd_data;
    wire rd_valid;
    integer failures = 0;

    osd_buffer dut (
        .clk(clk), .rst(rst), .wr_en(wr_en), .wr_x(wr_x), .wr_y(wr_y),
        .wr_data(wr_data), .rd_en(rd_en), .rd_x(rd_x), .rd_y(rd_y),
        .rd_data(rd_data), .rd_valid(rd_valid)
    );

    task write_pixel;
        input [11:0] address;
        input [1:0] value;
        begin
            @(negedge clk);
            wr_en = 1'b1;
            wr_y = address[11:8];
            wr_x = address[7:0];
            wr_data = value;
            @(posedge clk);
            #1;
            @(negedge clk);
            wr_en = 1'b0;
        end
    endtask

    task check_pixel;
        input [11:0] address;
        input [1:0] value;
        begin
            @(negedge clk);
            rd_en = 1'b1;
            rd_y = address[11:8];
            rd_x = address[7:0];
            @(posedge clk);
            #1;
            if (rd_valid !== 1'b1 || rd_data !== value) begin
                $display("FAIL address=%d expected=%b actual=%b valid=%b", address, value, rd_data, rd_valid);
                failures = failures + 1;
            end
            @(negedge clk);
            rd_en = 1'b0;
            @(posedge clk);
            #1;
            if (rd_valid !== 1'b0 || rd_data !== 2'd0) begin
                $display("FAIL disabled read at %d", address);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst = 1'b0;
        write_pixel(12'd0, 2'b00);
        write_pixel(12'd255, 2'b01);
        write_pixel(12'd256, 2'b10);
        write_pixel(12'd4095, 2'b11);
        check_pixel(12'd0, 2'b00);
        check_pixel(12'd255, 2'b01);
        check_pixel(12'd256, 2'b10);
        check_pixel(12'd4095, 2'b11);
        write_pixel(12'd255, 2'b11);
        check_pixel(12'd255, 2'b11);
        @(negedge clk);
        rst = 1'b1;
        #1;
        if (rd_valid !== 1'b0) begin
            $display("FAIL reset valid");
            failures = failures + 1;
        end
        if (failures == 0) $display("PASS tb_osd_buffer");
        else $fatal(1, "tb_osd_buffer failures=%0d", failures);
        $finish;
    end
endmodule
