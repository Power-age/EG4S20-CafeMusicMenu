`timescale 1ns/1ps

module tb_mask_slide;
    reg         clk         = 1'b0;
    reg         rst         = 1'b1;
    reg         page_changed= 1'b0;
    reg         trans_active= 1'b0;
    reg         frame_tick  = 1'b0;
    wire [9:0]  slide;

    integer errors = 0;
    integer ticks  = 0;
    integer t;

    mask_slide #(
        .MINWAIT (2)
    ) dut (
        .clk          (clk),
        .rst          (rst),
        .page_changed (page_changed),
        .trans_active (trans_active),
        .frame_tick   (frame_tick),
        .slide        (slide)
    );

    always #20 clk = ~clk;

    task frame;
        begin
            @(posedge clk);
            frame_tick <= 1'b1;
            @(posedge clk);
            frame_tick <= 1'b0;
        end
    endtask

    task check(input [8*40:1] tag, input [9:0] want);
        begin
            if (slide !== want) begin
                $display("FAIL %0s slide=%0d want=%0d", tag, slide, want);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        #100 rst = 1'b0;
        #100;
        check("reset", 10'd200);

        frame; #20;
        check("one_tick", 10'd193);

        begin : ramp
            integer n;
            n = 0;
            while (slide !== 10'd0 && n < 60) begin
                frame; #40;
                n = n + 1;
            end
            if (slide !== 10'd0) begin
                $display("FAIL ramp_no_zero");
                errors = errors + 1;
            end
            if (n != 28) begin
                $display("FAIL ramp_frames=%0d want=28", n);
                errors = errors + 1;
            end
            ticks = n;
        end

        frame; #20;
        check("hold_zero", 10'd0);

        trans_active <= 1'b1;
        page_changed <= 1'b1;
        @(posedge clk); #1;
        page_changed <= 1'b0;
        check("page_jump", 10'd200);

        frame; #20;
        check("hold1", 10'd200);

        frame; #20;
        check("hold2", 10'd200);

        frame; #20;
        check("frozen_trans_active", 10'd200);

        trans_active <= 1'b0;
        #100;
        frame; #20;
        check("resume_after_trans", 10'd193);

        page_changed <= 1'b1;
        @(posedge clk); #1;
        page_changed <= 1'b0;
        check("page_jump_no_trans", 10'd200);

        frame; #20;
        check("min_wait_blocks", 10'd200);

        frame; #20;
        check("min_wait_done", 10'd200);

        frame; #20;
        check("run_after_no_trans", 10'd193);

        if (errors == 0) $display("PASS tb_mask_slide");
        else             $display("FAIL tb_mask_slide errors=%0d", errors);
        $finish;
    end
endmodule
