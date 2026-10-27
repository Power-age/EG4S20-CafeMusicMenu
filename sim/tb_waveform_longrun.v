`timescale 1ns/1ps
module tb_waveform_longrun;
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
    integer frame;
    integer i;
    integer cycles;
    integer flips;
    reg last_front;
    reg [7:0] sample0;
    reg [7:0] sample127;
    reg [7:0] sample320;
    integer nonuniform_frames;

    waveform_ram dut (
        .clk(clk), .rst(rst), .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .block_done(block_done), .frame_pulse(frame_pulse), .video_de(video_de),
        .block_accept(block_accept), .front_valid(front_valid), .front_sel(front_sel),
        .rd_en(rd_en), .rd_addr(rd_addr), .rd_data(rd_data), .rd_valid(rd_valid)
    );

    always #1 clk = ~clk;

    function [7:0] value_for;
        input integer f;
        input integer index;
        integer mixed;
        begin
            mixed = (index * 37) ^ (f * 29) ^ ((index + f) >> 2);
            value_for = mixed[7:0];
        end
    endfunction

    task read_value;
        input [9:0] address;
        output [7:0] value;
        begin
            @(negedge clk);
            rd_en = 1'b1;
            rd_addr = address;
            @(posedge clk);
            @(negedge clk);
            value = rd_data;
            rd_en = 1'b0;
            @(posedge clk);
        end
    endtask

    initial begin
        clk=0; rst=1; wr_en=0; wr_addr=0; wr_data=0; block_done=0;
        frame_pulse=0; video_de=0; rd_en=0; rd_addr=0;
        errors=0; flips=0; nonuniform_frames=0;
        repeat(3) @(posedge clk);
        @(negedge clk); rst=0;
        last_front=front_sel;

        for (frame=0; frame<5000; frame=frame+1) begin
            wait(block_accept === 1'b1);
            for (i=0; i<640; i=i+1) begin
                @(negedge clk);
                wr_en=1'b1;
                wr_addr=i[9:0];
                wr_data=value_for(frame,i);
                @(posedge clk);
            end
            @(negedge clk);
            wr_en=1'b0;
            block_done=1'b1;
            @(posedge clk);
            @(negedge clk);
            block_done=1'b0;
            cycles=0;
            while ((front_sel==last_front) && (cycles<5000)) begin
                @(posedge clk);
                cycles=cycles+1;
            end
            if (front_sel==last_front) begin
                $display("FAIL longrun no flip frame=%0d",frame);
                errors=errors+1;
                frame=5000;
            end else begin
                flips=flips+1;
                last_front=front_sel;
                read_value(10'd0,sample0);
                read_value(10'd127,sample127);
                read_value(10'd320,sample320);
                if ((sample0!=sample127)||(sample127!=sample320))
                    nonuniform_frames=nonuniform_frames+1;
            end
        end

        if (flips!=5000) begin
            $display("FAIL longrun flips=%0d",flips);
            errors=errors+1;
        end
        if (nonuniform_frames<4990) begin
            $display("FAIL longrun nonuniform=%0d",nonuniform_frames);
            errors=errors+1;
        end
        if (errors==0)
            $display("WAVEFORM_LONGRUN PASS flips=%0d nonuniform=%0d",flips,nonuniform_frames);
        else
            $display("WAVEFORM_LONGRUN FAIL errors=%0d",errors);
        $finish;
    end

    initial begin
        #200000000;
        $display("WAVEFORM_LONGRUN TIMEOUT");
        $finish;
    end
endmodule
