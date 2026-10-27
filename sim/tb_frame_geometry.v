`timescale 1ns/1ps
//============================================================================
// tb_frame_geometry.v
// 用真实几何（640x480, ADDR_BITS=21, BURST_SIZE=128）逐点校验写地址序列：
//   第 k 个写入像素应落在  addr = (VFLIP ? (H-1-row) : row) * W + col
//   其中 row = k / W, col = k % W
// 这是"上电清 bank 为黑"与整帧图像写入共同依赖的映射，任何错位都会在这里暴露。
//============================================================================
module tb_frame_geometry;

    localparam ADDR_BITS  = 21;
    localparam BURST_BITS = 9;
    localparam BURST_SIZE = 128;
    localparam FW         = 640;
    localparam FH         = 480;
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

    integer k_f, k_n;
    integer err_f = 0, err_n = 0;
    integer exp_addr;
    integer row, col;

    always #4 clk = ~clk;

    frame_fifo_write
    #(
        .ADDR_BITS(ADDR_BITS), .BURST_BITS(BURST_BITS), .BURST_SIZE(BURST_SIZE),
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
        .ADDR_BITS(ADDR_BITS), .BURST_BITS(BURST_BITS), .BURST_SIZE(BURST_SIZE),
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

    // VFLIP=1：第 k 像素 -> 行 (FH-1-row)
    always @(posedge clk) begin
        if (!rst && en_f) begin
            row = k_f / FW;
            col = k_f % FW;
            exp_addr = (FH - 1 - row) * FW + col;
            if (ad_f !== exp_addr) begin
                if (err_f < 5) $display("  FLIP MISMATCH k=%0d addr=%0d expect=%0d", k_f, ad_f, exp_addr);
                err_f = err_f + 1;
            end
            k_f = k_f + 1;
        end
    end

    // VFLIP=0：第 k 像素 -> 行 row
    always @(posedge clk) begin
        if (!rst && en_n) begin
            row = k_n / FW;
            col = k_n % FW;
            exp_addr = row * FW + col;
            if (ad_n !== exp_addr) begin
                if (err_n < 5) $display("  NORM MISMATCH k=%0d addr=%0d expect=%0d", k_n, ad_n, exp_addr);
                err_n = err_n + 1;
            end
            k_n = k_n + 1;
        end
    end

    initial begin
        k_f = 0; k_n = 0;
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
        rdusedw   = 10'd1000;

        fork
            begin : wf wait (fin_f); end
            begin : wn wait (fin_n); end
        join
        repeat (20) @(posedge clk);

        $display("---- 640x480 整帧：VFLIP=1 写入 %0d 点，错 %0d ----", k_f, err_f);
        $display("---- 640x480 整帧：VFLIP=0 写入 %0d 点，错 %0d ----", k_n, err_n);

        if (k_f !== TOTAL) begin $display("  FAIL flip: 写入点数 %0d != %0d", k_f, TOTAL); err_f = err_f + 1; end
        if (k_n !== TOTAL) begin $display("  FAIL norm: 写入点数 %0d != %0d", k_n, TOTAL); err_n = err_n + 1; end

        if (err_f == 0 && err_n == 0) $display("==== GEOMETRY TEST PASS ====");
        else                          $display("==== GEOMETRY TEST FAIL (flip=%0d norm=%0d) ====", err_f, err_n);
        $finish;
    end

    initial begin
        #20_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
