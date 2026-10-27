`timescale 1ns/1ps
// 任务21：验证帧消隐离散刷新脉冲串时序
// frame_tick后：GUARD 12500拍，再600个脉冲（周期16、脉宽2），总窗口22100拍=176.8us
module tb_sdram_cmd;
    reg Clk, Rst;
    reg App_ref_allow, frame_tick;
    wire Sdr_init_done, Sdr_init_ref_vld, Sdr_busy, Sdr_rd_en;
    wire [31:0] Sdr_rd_dout;
    wire [20:0] App_wr_addr, App_rd_addr;
    wire [31:0] App_wr_din;
    wire [3:0] App_wr_dm;
    wire App_wr_en, App_rd_en;

    sdram dut(
        .Clk(Clk), .Clk_sft(Clk), .Rst(Rst),
        .App_ref_allow(App_ref_allow), .frame_tick(frame_tick),
        .Sdr_init_done(Sdr_init_done), .Sdr_init_ref_vld(Sdr_init_ref_vld),
        .Sdr_busy(Sdr_busy),
        .App_wr_en(App_wr_en), .App_wr_addr(App_wr_addr), .App_wr_dm(App_wr_dm),
        .App_wr_din(App_wr_din),
        .App_rd_en(App_rd_en), .App_rd_addr(App_rd_addr),
        .Sdr_rd_en(Sdr_rd_en), .Sdr_rd_dout(Sdr_rd_dout)
    );

    initial begin Clk=1'b0; forever #4 Clk=~Clk; end

    integer pulse_n, win_n, errors;
    reg prev_req, win_done;
    always @(posedge Clk or posedge Rst) begin
        if (Rst) begin pulse_n<=0; win_n<=0; prev_req<=1'b0; end
        else begin
            prev_req <= dut.app_ref_req_r;
            if (dut.app_ref_req_r && !prev_req) pulse_n <= pulse_n+1;
            if (dut.vblank_burst) win_n <= win_n+1;
        end
    end

    initial begin
        $display("==== tb_sdram_cmd (pulse train) start ====");
        Rst=1'b1; App_ref_allow=1'b0; frame_tick=1'b0; errors=0; win_done=1'b0;
        repeat(8) @(posedge Clk);
        Rst=1'b0;
        force dut.Sdr_init_done = 1'b1;
        App_ref_allow=1'b1;
        repeat(4) @(posedge Clk);
        frame_tick=1'b1; repeat(6) @(posedge Clk); frame_tick=1'b0;

        while ($time < 2000000 && !win_done) begin
            @(posedge Clk);
            if (pulse_n>0 && dut.app_ref_req_r==1'b0 && dut.vblank_burst==1'b0)
                win_done=1'b1;
        end

        $display("pulse_n=%0d (expect 600)", pulse_n);
        $display("win_n  =%0d (expect 22100)", win_n);
        if (pulse_n !== 600) begin $display("FAIL pulse count"); errors=errors+1; end
        if (win_n   !== 22100) begin $display("FAIL window length"); errors=errors+1; end
        if (win_n >= 140725) begin $display("FAIL window reaches active"); errors=errors+1; end

        if (errors==0) $display("==== PULSE TRAIN TIMING PASS ====");
        else $display("==== PULSE TRAIN FAIL errors=%0d ====", errors);
        $finish;
    end
endmodule
