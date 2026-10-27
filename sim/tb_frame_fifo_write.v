`timescale 1ns/1ps
//============================================================================
// tb_frame_fifo_write.v
// frame_fifo_write 写地址生成功能测试（时序二期 A / D 共用）
//   双 DUT 并行：dut_flip（WRITE_V_FLIP=1）、dut_norm（=0）
//   缩小参数：ADDR_BITS=16, BURST_SIZE=8, FRAME 8x4
//
//   场景 1（二期 A 基线）：width=3 height=2 off_x=1 off_y=1 len=6
//     VFLIP=1 : 17,18,19,9,10,11
//     VFLIP=0 : 9,10,11,17,18,19
//   场景 2（二期 D 边缘）：width=1 height=3 off_x=0 off_y=0 len=3
//     行跳转在第一个像素后就发生，压 width=1 的最紧时序
//     VFLIP=1 : 16,8,0
//     VFLIP=0 : 0,8,16
//============================================================================
module tb_frame_fifo_write;

    localparam ADDR_BITS  = 16;
    localparam BURST_BITS = 4;
    localparam BURST_SIZE = 8;
    localparam FW         = 8;
    localparam FH         = 4;

    localparam S1_W = 3, S1_H = 2, S1_X = 1, S1_Y = 1;
    localparam S1_LEN = S1_W * S1_H;
    localparam S2_W = 1, S2_H = 3, S2_X = 0, S2_Y = 0;
    localparam S2_LEN = S2_W * S2_H;

    reg                    clk;
    reg                    rst;
    reg                    sdr_init_done;
    reg  [9:0]             rdusedw;

    reg                    write_req;
    reg  [ADDR_BITS-1:0]   write_len;
    reg  [15:0]            act_w, act_h, off_x, off_y;
    reg  [1:0]             addr_idx;
    reg  [ADDR_BITS-1:0]   addr0, addr1, addr2, addr3;

    wire                   ack_flip, ack_norm;
    wire                   fin_flip, fin_norm;
    wire                   en_flip,  en_norm;
    wire [ADDR_BITS-1:0]   ad_flip,  ad_norm;
    wire                   aclr_flip, aclr_norm;

    reg                    phase;

    integer hist_flip  [0:63];
    integer hist_norm  [0:63];
    integer hist2_flip [0:63];
    integer hist2_norm [0:63];
    integer n_flip, n_norm, n2_flip, n2_norm;
    integer aclr_cnt_flip, aclr_cnt_norm;

    integer exp_flip  [0:5];
    integer exp_norm  [0:5];
    integer exp2_flip [0:2];
    integer exp2_norm [0:2];

    integer errors = 0;
    integer i;

    always #4 clk = ~clk;

    frame_fifo_write
    #(
        .ADDR_BITS    (ADDR_BITS ),
        .BURST_BITS   (BURST_BITS),
        .BURST_SIZE   (BURST_SIZE),
        .WRITE_V_FLIP (1         ),
        .FRAME_WIDTH  (FW        ),
        .FRAME_HEIGHT (FH        )
    )
    dut_flip
    (
        .rst                   (rst          ),
        .mem_clk               (clk          ),
        .Sdr_init_done         (sdr_init_done),
        .Sdr_init_ref_vld      (1'b0         ),
        .Sdr_busy              (1'b0         ),
        .App_rd_busy           (1'b0         ),
        .O_wr_busy             (             ),
        .App_wr_en             (en_flip      ),
        .App_wr_addr           (ad_flip      ),
        .write_req             (write_req    ),
        .write_req_ack         (ack_flip     ),
        .write_finish          (fin_flip     ),
        .write_addr_0          (addr0        ),
        .write_addr_1          (addr1        ),
        .write_addr_2          (addr2        ),
        .write_addr_3          (addr3        ),
        .write_addr_index      (addr_idx     ),
        .write_len             (write_len    ),
        .write_active_width    (act_w        ),
        .write_active_height   (act_h        ),
        .write_active_offset_x (off_x        ),
        .write_active_offset_y (off_y        ),
        .fifo_aclr             (aclr_flip    ),
        .rdusedw               (rdusedw      )
    );

    frame_fifo_write
    #(
        .ADDR_BITS    (ADDR_BITS ),
        .BURST_BITS   (BURST_BITS),
        .BURST_SIZE   (BURST_SIZE),
        .WRITE_V_FLIP (0         ),
        .FRAME_WIDTH  (FW        ),
        .FRAME_HEIGHT (FH        )
    )
    dut_norm
    (
        .rst                   (rst          ),
        .mem_clk               (clk          ),
        .Sdr_init_done         (sdr_init_done),
        .Sdr_init_ref_vld      (1'b0         ),
        .Sdr_busy              (1'b0         ),
        .App_rd_busy           (1'b0         ),
        .O_wr_busy             (             ),
        .App_wr_en             (en_norm      ),
        .App_wr_addr           (ad_norm      ),
        .write_req             (write_req    ),
        .write_req_ack         (ack_norm     ),
        .write_finish          (fin_norm     ),
        .write_addr_0          (addr0        ),
        .write_addr_1          (addr1        ),
        .write_addr_2          (addr2        ),
        .write_addr_3          (addr3        ),
        .write_addr_index      (addr_idx     ),
        .write_len             (write_len    ),
        .write_active_width    (act_w        ),
        .write_active_height   (act_h        ),
        .write_active_offset_x (off_x        ),
        .write_active_offset_y (off_y        ),
        .fifo_aclr             (aclr_norm    ),
        .rdusedw               (rdusedw      )
    );

    always @(posedge clk) begin
        if (rst) begin
            n_flip        <= 0;
            n_norm        <= 0;
            n2_flip       <= 0;
            n2_norm       <= 0;
            aclr_cnt_flip <= 0;
            aclr_cnt_norm <= 0;
        end else begin
            if (!phase) begin
                if (en_flip && n_flip < 64) begin
                    hist_flip[n_flip] <= ad_flip;
                    n_flip            <= n_flip + 1;
                end
                if (en_norm && n_norm < 64) begin
                    hist_norm[n_norm] <= ad_norm;
                    n_norm            <= n_norm + 1;
                end
            end else begin
                if (en_flip && n2_flip < 64) begin
                    hist2_flip[n2_flip] <= ad_flip;
                    n2_flip             <= n2_flip + 1;
                end
                if (en_norm && n2_norm < 64) begin
                    hist2_norm[n2_norm] <= ad_norm;
                    n2_norm             <= n2_norm + 1;
                end
            end
            if (aclr_flip) aclr_cnt_flip <= aclr_cnt_flip + 1;
            if (aclr_norm) aclr_cnt_norm <= aclr_cnt_norm + 1;
        end
    end

    initial begin
        clk           = 0;
        rst           = 1;
        sdr_init_done = 0;
        rdusedw       = 0;
        write_req     = 0;
        write_len     = S1_LEN;
        act_w         = S1_W;
        act_h         = S1_H;
        off_x         = S1_X;
        off_y         = S1_Y;
        addr_idx      = 2'd0;
        addr0         = 0;
        addr1         = 0;
        addr2         = 0;
        addr3         = 0;
        phase         = 1'b0;

        exp_flip[0] = 17; exp_flip[1] = 18; exp_flip[2] = 19;
        exp_flip[3] = 9;  exp_flip[4] = 10; exp_flip[5] = 11;
        exp_norm[0] = 9;  exp_norm[1] = 10; exp_norm[2] = 11;
        exp_norm[3] = 17; exp_norm[4] = 18; exp_norm[5] = 19;

        exp2_flip[0] = 16; exp2_flip[1] = 8; exp2_flip[2] = 0;
        exp2_norm[0] = 0;  exp2_norm[1] = 8; exp2_norm[2] = 16;

        repeat (5) @(posedge clk);
        rst = 0;
        repeat (3) @(posedge clk);
        sdr_init_done = 1;
        repeat (2) @(posedge clk);

        // ---------------- 场景 1 ----------------
        write_req = 1;
        wait (ack_flip == 1'b1 && ack_norm == 1'b1);
        repeat (2) @(posedge clk);
        write_req = 0;
        rdusedw   = 10;
        fork
            begin : w1f wait (fin_flip == 1'b1); end
            begin : w1n wait (fin_norm == 1'b1); end
        join
        repeat (10) @(posedge clk);

        $display("---- S1 VFLIP=1 : %0d 拍 ----", n_flip);
        for (i = 0; i < n_flip; i = i + 1) $display("   S1 flip addr[%0d] = %0d", i, hist_flip[i]);
        $display("---- S1 VFLIP=0 : %0d 拍 ----", n_norm);
        for (i = 0; i < n_norm; i = i + 1) $display("   S1 norm addr[%0d] = %0d", i, hist_norm[i]);

        // ---------------- 场景 2：width=1 ----------------
        phase     = 1'b1;
        rdusedw   = 0;
        act_w     = S2_W;
        act_h     = S2_H;
        off_x     = S2_X;
        off_y     = S2_Y;
        write_len = S2_LEN;
        repeat (4) @(posedge clk);

        write_req = 1;
        wait (ack_flip == 1'b1 && ack_norm == 1'b1);
        repeat (2) @(posedge clk);
        write_req = 0;
        rdusedw   = 10;
        fork
            begin : w2f wait (fin_flip == 1'b1); end
            begin : w2n wait (fin_norm == 1'b1); end
        join
        repeat (10) @(posedge clk);

        $display("---- S2 VFLIP=1 : %0d 拍 ----", n2_flip);
        for (i = 0; i < n2_flip; i = i + 1) $display("   S2 flip addr[%0d] = %0d", i, hist2_flip[i]);
        $display("---- S2 VFLIP=0 : %0d 拍 ----", n2_norm);
        for (i = 0; i < n2_norm; i = i + 1) $display("   S2 norm addr[%0d] = %0d", i, hist2_norm[i]);

        // ---------------- 判定 ----------------
        if (n_flip !== S1_LEN)  begin $display("  FAIL S1 flip 拍数: 期望 %0d 实际 %0d", S1_LEN, n_flip);  errors=errors+1; end
        if (n_norm !== S1_LEN)  begin $display("  FAIL S1 norm 拍数: 期望 %0d 实际 %0d", S1_LEN, n_norm);  errors=errors+1; end
        if (n2_flip !== S2_LEN) begin $display("  FAIL S2 flip 拍数: 期望 %0d 实际 %0d", S2_LEN, n2_flip); errors=errors+1; end
        if (n2_norm !== S2_LEN) begin $display("  FAIL S2 norm 拍数: 期望 %0d 实际 %0d", S2_LEN, n2_norm); errors=errors+1; end
        if (aclr_cnt_flip < 2)  begin $display("  FAIL flip: fifo_aclr 只拉高 %0d 次（期望 >=2）", aclr_cnt_flip); errors=errors+1; end
        if (aclr_cnt_norm < 2)  begin $display("  FAIL norm: fifo_aclr 只拉高 %0d 次（期望 >=2）", aclr_cnt_norm); errors=errors+1; end

        for (i = 0; i < S1_LEN; i = i + 1) begin
            if (i < n_flip && hist_flip[i] !== exp_flip[i]) begin
                $display("  FAIL S1 flip addr[%0d]: 期望 %0d 实际 %0d", i, exp_flip[i], hist_flip[i]); errors=errors+1; end
            if (i < n_norm && hist_norm[i] !== exp_norm[i]) begin
                $display("  FAIL S1 norm addr[%0d]: 期望 %0d 实际 %0d", i, exp_norm[i], hist_norm[i]); errors=errors+1; end
        end
        for (i = 0; i < S2_LEN; i = i + 1) begin
            if (i < n2_flip && hist2_flip[i] !== exp2_flip[i]) begin
                $display("  FAIL S2 flip addr[%0d]: 期望 %0d 实际 %0d", i, exp2_flip[i], hist2_flip[i]); errors=errors+1; end
            if (i < n2_norm && hist2_norm[i] !== exp2_norm[i]) begin
                $display("  FAIL S2 norm addr[%0d]: 期望 %0d 实际 %0d", i, exp2_norm[i], hist2_norm[i]); errors=errors+1; end
        end

        if (errors == 0)
            $display("==== FRAME_FIFO_WRITE TEST PASS ====");
        else
            $display("==== FRAME_FIFO_WRITE TEST FAIL (%0d errors) ====", errors);
        $finish;
    end

    initial begin
        #5_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
