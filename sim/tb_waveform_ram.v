`timescale 1ns/1ps
module tb_waveform_ram;
    reg clk;
    reg rst;
    reg wr_en;
    reg [9:0] wr_addr;
    reg [7:0] wr_data;
    reg block_done;
    reg frame_pulse;
    reg video_de;
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
    reg start_front;

    waveform_ram dut (
        .clk(clk), .rst(rst), .wr_en(wr_en), .wr_addr(wr_addr),
        .wr_data(wr_data), .block_done(block_done), .frame_pulse(frame_pulse),
        .video_de(video_de), .block_accept(block_accept),
        .front_valid(front_valid), .front_sel(front_sel),
        .rd_en(rd_en), .rd_addr(rd_addr), .rd_data(rd_data), .rd_valid(rd_valid)
    );

    always #20 clk = ~clk;

    function [7:0] raw_value;
        input integer index;
        integer mixed;
        begin
            mixed = (index * 37) ^ (index >> 1);
            raw_value = mixed[7:0];
        end
    endfunction

    function [7:0] spatial_ref;
        input integer index;
        integer left_i;
        integer right_i;
        integer sum;
        begin
            left_i = (index == 0) ? 0 : index - 1;
            right_i = (index == 639) ? 639 : index + 1;
            sum = raw_value(left_i) + 2 * raw_value(index) + raw_value(right_i) + 2;
            spatial_ref = sum >> 2;
        end
    endfunction

    task write_back;
        begin
            for (i = 0; i < 640; i = i + 1) begin
                @(negedge clk);
                wr_en = 1'b1;
                wr_addr = i[9:0];
                wr_data = raw_value(i);
                @(posedge clk);
            end
            @(negedge clk);
            wr_en = 1'b0;
            block_done = 1'b1;
            @(posedge clk);
            @(negedge clk);
            block_done = 1'b0;
        end
    endtask

    task wait_commit;
        begin
            cycles = 0;
            start_front = front_sel;
            while ((front_sel == start_front) && (cycles < 6000)) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
            if (front_sel == start_front || cycles >= 6000) begin
                $display("FAIL filter commit cycles=%0d", cycles);
                errors = errors + 1;
            end
            if (cycles >= 5000) begin
                $display("FAIL filter budget cycles=%0d", cycles);
                errors = errors + 1;
            end
        end
    endtask

    task read_check;
        input [9:0] address;
        input [7:0] expected;
        begin
            @(negedge clk);
            rd_en = 1'b1;
            rd_addr = address;
            @(posedge clk);
            @(negedge clk);
            if (!rd_valid || rd_data !== expected) begin
                $display("FAIL filtered read addr=%0d got=%0d expected=%0d valid=%b", address, rd_data, expected, rd_valid);
                errors = errors + 1;
            end
            rd_en = 1'b0;
            @(posedge clk);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        wr_en = 1'b0;
        wr_addr = 10'd0;
        wr_data = 8'd0;
        block_done = 1'b0;
        frame_pulse = 1'b0;
        video_de = 1'b0;
        rd_en = 1'b0;
        rd_addr = 10'd0;
        errors = 0;
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        write_back;
        wait_commit;
        if (!front_valid || !block_accept) begin
            $display("FAIL first commit valid=%b accept=%b", front_valid, block_accept);
            errors = errors + 1;
        end
        read_check(10'd0, spatial_ref(0));
        read_check(10'd1, spatial_ref(1));
        read_check(10'd2, spatial_ref(2));
        read_check(10'd127, spatial_ref(127));
        read_check(10'd320, spatial_ref(320));
        read_check(10'd638, spatial_ref(638));
        read_check(10'd639, spatial_ref(639));

        write_back;
        start_front = front_sel;
        wait (dut.filter_state == 4'd5);
        video_de = 1'b1;
        @(posedge clk);
        repeat (20) @(posedge clk);
        if (front_sel !== start_front || block_accept !== 1'b0) begin
            $display("FAIL active interruption front=%b accept=%b", front_sel, block_accept);
            errors = errors + 1;
        end
        video_de = 1'b0;
        wait_commit;
        read_check(10'd0, spatial_ref(0));
        read_check(10'd1, spatial_ref(1));
        read_check(10'd2, spatial_ref(2));
        read_check(10'd127, spatial_ref(127));
        read_check(10'd320, spatial_ref(320));
        read_check(10'd638, spatial_ref(638));
        read_check(10'd639, spatial_ref(639));

        if (errors == 0)
            $display("WAVEFORM_RAM PASS");
        else
            $display("WAVEFORM_RAM FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        #100000000;
        $display("WAVEFORM_RAM TIMEOUT");
        $finish;
    end
endmodule
