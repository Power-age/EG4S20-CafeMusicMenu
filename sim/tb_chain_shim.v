`timescale 1ns/1ps
module tb_chain_shim;
    reg clk, rst;
    reg load_start;
    reg [31:0] start_cluster;
    reg [7:0]  spc;
    reg [31:0] fat_start, data_start, max_cluster;
    reg        bmp_req;
    reg [31:0] bmp_k;

    wire [7:0]  to_bmp_data;
    wire        to_bmp_valid, to_bmp_end, to_bmp_error;
    wire        sd_req;
    wire [31:0] sd_addr;
    reg  [7:0]  sd_data;
    reg         sd_valid, sd_end;

    reg bad_mode;

    fat32_chain_reader dut(
        .clk(clk), .rst(rst),
        .load_start(load_start), .start_cluster(start_cluster),
        .fat_start_lba(fat_start), .data_start_lba(data_start),
        .max_cluster(max_cluster), .spc(spc),
        .bmp_req(bmp_req), .bmp_k(bmp_k),
        .to_bmp_data(to_bmp_data), .to_bmp_valid(to_bmp_valid),
        .to_bmp_end(to_bmp_end), .to_bmp_error(to_bmp_error),
        .sd_req(sd_req), .sd_addr(sd_addr),
        .sd_data(sd_data), .sd_valid(sd_valid), .sd_end(sd_end)
    );

    // ---- SD 单块主模型 ----
    reg [2:0]  m_st;
    reg [31:0] m_lba;
    reg [8:0]  m_cnt;
    reg [3:0]  dly;

    function [7:0] fat_byte;
        input [31:0] lba;
        input [8:0]  b;
        reg [31:0] sector_idx;
        reg [31:0] cl;
        reg [31:0] entry;
        begin
            sector_idx = lba - fat_start;
            cl = (sector_idx << 7) + {23'd0, b[8:2]};
            if (bad_mode && cl==32'd2)
                entry = 32'h0FFFFFF8;
            else if (cl>=32'd2 && cl<32'd200)
                entry = cl + 32'd1;
            else
                entry = 32'h0FFFFFF8;
            fat_byte = entry[b[1:0]*8 +: 8];
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            m_st<=0; sd_valid<=0; sd_end<=0; sd_data<=0;
        end else begin
            sd_valid<=0; sd_end<=0;
            case (m_st)
                3'd0: if (sd_req) begin m_lba<=sd_addr; m_cnt<=0; dly<=0; m_st<=3'd1; end
                3'd1: begin dly<=dly+1; if(dly==4'd2) m_st<=3'd2; end
                3'd2: begin
                    sd_valid<=1;
                    if (m_lba>=fat_start && m_lba<(fat_start+2))
                        sd_data<=fat_byte(m_lba,m_cnt);
                    else
                        sd_data<=m_lba[7:0] ^ m_cnt[7:0];
                    if (m_cnt==9'd511) begin sd_end<=1; m_st<=3'd3; end
                    m_cnt<=m_cnt+1;
                end
                3'd3: m_st<=3'd0;
            endcase
        end
    end

    // ---- 场景1：时钟驱动推进 k ----
    reg scen1_run;
    reg [31:0] drv_k;
    reg [8:0]  chk_cnt;
    integer errors, sectors_done;
    reg [31:0] expect_phys;
    reg [7:0]  expect_byte;

    always @(posedge clk) begin
        if (rst) begin
            drv_k<=0; bmp_k<=0;
        end else if (scen1_run) begin
            if (to_bmp_end) begin
                if (drv_k < 32'd1040) begin
                    drv_k  <= drv_k + 32'd1;
                    bmp_k  <= drv_k + 32'd1;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            chk_cnt<=0; errors=0; sectors_done=0;
        end else if (scen1_run) begin
            if (to_bmp_valid) begin
                expect_phys = data_start + drv_k;
                expect_byte = expect_phys[7:0] ^ chk_cnt[7:0];
                if (to_bmp_data!==expect_byte) begin
                    if (errors<5)
                        $display("BYTE MISMATCH k=%0d b=%0d got=%h exp=%h",
                                  drv_k,chk_cnt,to_bmp_data,expect_byte);
                    errors=errors+1;
                end
                chk_cnt<=chk_cnt+1;
            end
            if (to_bmp_end) begin
                if ((chk_cnt + {8'd0,to_bmp_valid})!==9'd512) begin
                    $display("LEN MISMATCH k=%0d cnt=%0d",drv_k,chk_cnt);
                    errors=errors+1;
                end
                chk_cnt<=0;
                sectors_done=sectors_done+1;
            end
        end
    end

    // ---- 场景2：错误锁存 ----
    reg saw_error;
    always @(posedge clk) begin
        if (rst) saw_error<=0;
        else if (to_bmp_error) saw_error<=1;
    end

    integer timeout_cycles;
    initial begin
        clk=0; forever #5 clk=~clk;
    end

    // debug：场景2 状态跟踪
    reg [3:0] last_st;
    always @(posedge clk) begin
        if (bad_mode && dut.state!==last_st) begin
            $display("DBG state=%0d addr=%0d cache=%0d pos=%0d cl=%0d ds=%0d fs=%0d sh=%0d",
                      dut.state,dut.sd_addr,dut.cache_valid,dut.cur_chain_pos,
                      dut.cur_cluster,dut.data_start_r,dut.fat_start_r,dut.spc_shift_r);
            last_st<=dut.state;
        end
    end

    initial begin
        rst=1; load_start=0; bmp_req=0; bmp_k=0; bad_mode=0; scen1_run=0;
        spc=8; fat_start=100; data_start=1000; max_cluster=1000;
        start_cluster=2;
        repeat(5) @(posedge clk); rst=0; repeat(3) @(posedge clk);

        // 场景1：连续文件 k=0..1040（跨簇8 与 FAT 扇区边界簇128）
        bad_mode=0;
        drv_k=0; bmp_k=0; scen1_run=1;
        @(posedge clk); load_start=1; @(posedge clk); load_start=0;
        repeat(3) @(posedge clk);   // 模拟 bmp_read 延迟一拍后才发起 read
        bmp_req=1;
        timeout_cycles=0;
        while (sectors_done<1041 && timeout_cycles<4000000) begin
            @(posedge clk); timeout_cycles=timeout_cycles+1;
        end
        scen1_run=0; bmp_req=0; repeat(4) @(posedge clk);
        if (errors==0 && sectors_done==1041) $display("SCEN1 CONTIGUOUS PASS");
        else $display("SCEN1 FAIL errors=%0d sectors=%0d",errors,sectors_done);

        // 场景2：提前 EOC 必须报错
        rst=1; repeat(3) @(posedge clk); rst=0; repeat(3) @(posedge clk);
        bad_mode=1;
        @(posedge clk); load_start=1; @(posedge clk); load_start=0;
        bmp_req=1; bmp_k=8;
        timeout_cycles=0;
        while (!saw_error && timeout_cycles<200000) begin
            @(posedge clk); timeout_cycles=timeout_cycles+1;
        end
        if (saw_error) $display("SCEN2 BAD-CHAIN ERROR PASS");
        else $display("SCEN2 FAIL: no error");
        bmp_req=0;
        #50 $finish;
    end
endmodule
