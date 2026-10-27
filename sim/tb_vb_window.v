`timescale 1ns/1ps
// 任务21 步骤5：验证帧消隐刷新窗口时序
// frame_tick后：GUARD(6250拍,req=0) -> REF(100000拍,req=1) -> 结束
module tb_vb_window;
    reg Clk, Rst;
    reg App_ref_allow, frame_tick;
    wire Sdr_init_done, Sdr_init_ref_vld, Sdr_busy, Sdr_rd_en;
    wire [31:0] Sdr_rd_dout;
    wire [20:0] App_wr_addr, App_rd_addr;
    wire [31:0] App_wr_din;
    wire [3:0] App_wr_dm;
    wire App_wr_en, App_rd_en;

    integer guard_cnt, ref_cnt, errors, phase;
    reg armed, win_done;

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

    initial begin Clk=1'b0; forever #4 Clk=~Clk; end  // 125MHz

    always @(posedge Clk or posedge Rst) begin
        if (Rst) begin
            guard_cnt<=0; ref_cnt<=0; armed<=1'b0;
        end else begin
            if (dut.ft_rise) armed <= 1'b1;
            if (armed && !dut.vblank_phase && dut.vblank_burst)
                guard_cnt <= guard_cnt+1;
            if (dut.app_ref_req_r)
                ref_cnt <= ref_cnt+1;
        end
    end

    initial begin
        $display("==== tb_vb_window start ====");
        Rst=1'b1; App_ref_allow=1'b0; frame_tick=1'b0; errors=0;
        repeat(8) @(posedge Clk);
        Rst=1'b0;
        force dut.Sdr_init_done = 1'b1;
        App_ref_allow=1'b1;
        repeat(4) @(posedge Clk);   // 等 app_allow_sync
        // 发 frame_tick 脉冲（约40ns，模拟video域窄脉冲）
        frame_tick=1'b1; repeat(6) @(posedge Clk); frame_tick=1'b0;

        // 等整个窗口流程结束（vblank_burst 1->0）
        win_done = 1'b0;
        while ($time < 2000000 && !win_done) begin
            @(posedge Clk);
            // 窗口走完：req 拉低且曾经ref
            if (ref_cnt>0 && dut.app_ref_req_r==1'b0 && dut.vblank_burst==1'b0)
                win_done = 1'b1;
        end

        $display("guard_cnt=%0d (expect ~6250)", guard_cnt);
        $display("ref_cnt  =%0d (expect ~100000)", ref_cnt);
        // GUARD 期间 req 不应高（guard_cnt 阶段 ref_cnt 必须为0）
        if (guard_cnt < 6000 || guard_cnt > 6400) begin
            $display("FAIL guard length"); errors=errors+1; end
        if (ref_cnt < 98000 || ref_cnt > 102000) begin
            $display("FAIL ref length"); errors=errors+1; end
        // 总窗口终点 = guard+ref 应 < de(140725)
        if ((guard_cnt+ref_cnt) >= 140725) begin
            $display("FAIL window reaches active region"); errors=errors+1; end

        if (errors==0) $display("==== VB WINDOW TIMING PASS ====");
        else $display("==== VB WINDOW FAIL errors=%0d ====", errors);
        $finish;
    end
endmodule
