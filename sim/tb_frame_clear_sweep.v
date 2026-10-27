`timescale 1ns/1ps
//============================================================================
// tb_frame_clear_sweep.v
// 针对"上电清 bank 为黑"的整帧写入做地址覆盖验证。
//   场景：width=FRAME_WIDTH, height=FRAME_HEIGHT, offset=0, len=FRAME_W*FRAME_H
//   要求：写出的地址恰好覆盖 [0, FRAME_W*FRAME_H-1] 各一次，不重不漏。
//   两个 DUT 分别覆盖 VFLIP=1（清屏启用）与 VFLIP=0。
//============================================================================
module tb_frame_clear_sweep;

    localparam ADDR_BITS  = 16;
    localparam BURST_BITS = 4;
    localparam BURST_SIZE = 8;
    localparam FW         = 8;
    localparam FH         = 4;
    localparam TOTAL      = FW * FH;

    reg                    clk;
    reg                    rst;
    reg                    sdr_init_done;
    reg  [9:0]             rdusedw;
    reg                    write_req;
    reg  [ADDR_BITS-1:0]   write_len;
    reg  [15:0]            act_w, act_h, off_x, off_y;
    reg  [1:0]             addr_idx;
    reg  [ADDR_BITS-1:0]   addr0, addr1, addr2, addr3;

    wire                   ack_f, ack_n;
    wire                   fin_f, fin_n;
    wire                   en_f,  en_n;
    wire [ADDR_BITS-1:0]   ad_f,  ad_n;
    wire                   aclr_f, aclr_n;

    reg  seen_f [0:255];
    reg  seen_n [0:255];
    integer n_f, n_n;
    integer dup_f, dup_n;
    integer errors = 0;
    integer i;

    always #4 clk = ~clk;

    frame_fifo_write
    #(
        .ADDR_BITS (ADDR_BITS), .BURST_BITS(BURST_BITS), .BURST_SIZE(BURST_SIZE),
        .WRITE_V_FLIP(1), .FRAME_WIDTH(FW), .FRAME_HEIGHT(FH)
    ) dut_f (
        .rst(rst), .mem_clk(clk), .Sdr_init_done(sdr_init_done),
        .Sdr_init_ref_vld(1'b0), .Sdr_busy(1'b0), .App_rd_busy(1'b0),
        .O_wr_busy(), .App_wr_en(en_f), .App_wr_addr(ad_f),
        .write_req(write_req), .write_req_ack(ack_f), .write_finish(fin_f),
        .write_addr_0(addr0), .write_addr_1(addr1), .write_addr_2(addr2), .write_addr_3(addr3),
        .write_addr_index(addr_idx), .write_len(write_len),
        .write_active_width(act_w), .write_active_height(act_h),
        .write_active_offset_x(off_x), .write_active_offset_y(off_y),
        .fifo_aclr(aclr_f), .rdusedw(rdusedw)
    );

    frame_fifo_write
    #(
        .ADDR_BITS (ADDR_BITS), .BURST_BITS(BURST_BITS), .BURST_SIZE(BURST_SIZE),
        .WRITE_V_FLIP(0), .FRAME_WIDTH(FW), .FRAME_HEIGHT(FH)
    ) dut_n (
        .rst(rst), .mem_clk(clk), .Sdr_init_done(sdr_init_done),
        .Sdr_init_ref_vld(1'b0), .Sdr_busy(1'b0), .App_rd_busy(1'b0),
        .O_wr_busy(), .App_wr_en(en_n), .App_wr_addr(ad_n),
        .write_req(write_req), .write_req_ack(ack_n), .write_finish(fin_n),
        .write_addr_0(addr0), .write_addr_1(addr1), .write_addr_2(addr2), .write_addr_3(addr3),
        .write_addr_index(addr_idx), .write_len(write_len),
        .write_active_width(act_w), .write_active_height(act_h),
        .write_active_offset_x(off_x), .write_active_offset_y(off_y),
        .fifo_aclr(aclr_n), .rdusedw(rdusedw)
    );

    initial begin
        for (i = 0; i < 256; i = i + 1) begin seen_f[i] = 1'b0; seen_n[i] = 1'b0; end
    end

    always @(posedge clk) begin
        if (rst) begin
            n_f <= 0; n_n <= 0; dup_f <= 0; dup_n <= 0;
        end else begin
            if (en_f) begin
                if (seen_f[ad_f]) dup_f <= dup_f + 1;
                else begin seen_f[ad_f] <= 1'b1; n_f <= n_f + 1; end
            end
            if (en_n) begin
                if (seen_n[ad_n]) dup_n <= dup_n + 1;
                else begin seen_n[ad_n] <= 1'b1; n_n <= n_n + 1; end
            end
        end
    end

    initial begin
        clk = 0; rst = 1; sdr_init_done = 0; rdusedw = 0; write_req = 0;
        write_len = TOTAL; act_w = FW; act_h = FH; off_x = 0; off_y = 0;
        addr_idx = 2'd0; addr0 = 0; addr1 = 0; addr2 = 0; addr3 = 0;

        repeat (5) @(posedge clk);
        rst = 0;
        repeat (3) @(posedge clk);
        sdr_init_done = 1;
        repeat (2) @(posedge clk);

        write_req = 1;
        wait (ack_f && ack_n);
        repeat (2) @(posedge clk);
        write_req = 0;
        rdusedw   = 10;

        fork
            begin : wf wait (fin_f); end
            begin : wn wait (fin_n); end
        join
        repeat (10) @(posedge clk);

        $display("---- 整帧写入：VFLIP=1 覆盖 %0d 个地址，重复 %0d 次 ----", n_f, dup_f);
        $display("---- 整帧写入：VFLIP=0 覆盖 %0d 个地址，重复 %0d 次 ----", n_n, dup_n);

        if (n_f !== TOTAL) begin $display("  FAIL flip: 期望覆盖 %0d 个地址，实际 %0d", TOTAL, n_f); errors=errors+1; end
        if (n_n !== TOTAL) begin $display("  FAIL norm: 期望覆盖 %0d 个地址，实际 %0d", TOTAL, n_n); errors=errors+1; end
        if (dup_f !== 0)   begin $display("  FAIL flip: 有 %0d 个地址被重复写", dup_f); errors=errors+1; end
        if (dup_n !== 0)   begin $display("  FAIL norm: 有 %0d 个地址被重复写", dup_n); errors=errors+1; end

        for (i = 0; i < TOTAL; i = i + 1) begin
            if (!seen_f[i]) begin $display("  FAIL flip: 地址 %0d 从未被写", i); errors=errors+1; end
            if (!seen_n[i]) begin $display("  FAIL norm: 地址 %0d 从未被写", i); errors=errors+1; end
        end

        if (errors == 0) $display("==== CLEAR SWEEP TEST PASS ====");
        else             $display("==== CLEAR SWEEP TEST FAIL (%0d errors) ====", errors);
        $finish;
    end

    initial begin
        #2_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
