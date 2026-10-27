`timescale 1ns/1ps
// 任务21 步骤5 验证：拔卡保持最后帧 + 重插复刻上电重载
// 行为化：sd_init_done 可控（上电/拔卡/重插）；scanner 完成用脉冲 scn_scan_done + resource_valid 模拟；
//         bmp_read/写帧下游用 G 序列驱动。scan_phase / scan_done_lvl / img_found_count 走真实逻辑。
module tb_step5_reload;
    reg clk, rst;
    reg key_next, key_auto, sw_dir;
    wire [3:0] state_code, hang_dbg, bank_valid_out;
    reg  [15:0] bmp_width, bmp_height;
    wire display_valid;
    wire osd_auto_play_en;
    wire [15:0] d_aw, d_ah, d_aox, d_aoy;
    reg  write_finish_toggle;
    wire [1:0] write_buf_idx, disp_buf_idx;
    wire write_req;
    reg  write_req_ack;
    wire [20:0] write_len;
    wire [15:0] w_aw, w_ah, w_aox, w_aoy;
    wire write_en;
    wire [31:0] write_data;
    wire SD_nCS, SD_DCLK, SD_MOSI;
    reg  SD_MISO;
    wire [1:0] img_idx_out;

    integer errors, watchdog, k;
    integer ntries;
    integer tries[0:9];
    integer scan_start_cnt;

    reg sd_init_force;
    reg clr_driver;

    // 下游加载结果驱动 FSM
    reg [4:0] dst;
    localparam D0=5'd0, G1=5'd1, G2=5'd2, G3=5'd3, G4=5'd4,
               G5=5'd5, G6=5'd6, G7=5'd7;
    reg [1:0] dli;
    reg [15:0] gcnt;
    reg        have_last;
    reg [1:0]  last_done;

    // scanner 完成驱动
    reg [2:0] sst;
    reg [15:0] scnt;

    sd_card_bmp dut(
        .clk(clk), .rst(rst),
        .key_next(key_next), .key_auto(key_auto),
        .state_code(state_code), .hang_dbg(hang_dbg),
        .bank_valid_out(bank_valid_out),
        .bmp_width(bmp_width), .bmp_height(bmp_height),
        .display_valid(display_valid),
        .osd_auto_play_en(osd_auto_play_en),
        .display_active_width(d_aw), .display_active_height(d_ah),
        .display_active_offset_x(d_aox), .display_active_offset_y(d_aoy),
        .write_finish_toggle(write_finish_toggle),
        .write_buf_idx(write_buf_idx), .disp_buf_idx(disp_buf_idx),
        .write_req(write_req), .write_req_ack(write_req_ack),
        .write_len(write_len),
        .write_active_width(w_aw), .write_active_height(w_ah),
        .write_active_offset_x(w_aox), .write_active_offset_y(w_aoy),
        .write_en(write_en), .write_data(write_data),
        .SD_nCS(SD_nCS), .SD_DCLK(SD_DCLK),
        .SD_MOSI(SD_MOSI), .SD_MISO(SD_MISO),
        .img_idx_out(img_idx_out), .sw_dir(sw_dir)
    );

    task apply_static_force;
        begin
            force dut.bmp_ready          = 1'b1;
            force dut.bmp_active_width   = 16'd640;
            force dut.bmp_active_height  = 16'd480;
            force dut.bmp_active_offset_x= 16'd0;
            force dut.bmp_active_offset_y= 16'd0;
            force dut.bmp_active_pixel_count = 21'd307200;
            force dut.scn_resource_valid = 4'hF;
        end
    endtask

    // ---- scanner 完成驱动：scan_phase 拉高后延时，给 scn_scan_done 脉冲 ----
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sst <= 3'd0; scnt <= 16'd0;
            force dut.scn_scan_done = 1'b0;
        end else begin
            case (sst)
                3'd0: if (dut.scan_phase) begin sst <= 3'd1; scnt <= 16'd0; end
                3'd1: if (scnt >= 16'd8) begin
                          force dut.scn_scan_done = 1'b1; sst <= 3'd2;
                      end else scnt <= scnt + 16'd1;
                3'd2: sst <= 3'd3;
                3'd3: begin force dut.scn_scan_done = 1'b0; sst <= 3'd0; end
            endcase
        end
    end

    // ---- 下游写帧驱动 FSM ----
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            dst <= D0; gcnt <= 16'd0; dli <= 2'd0;
            have_last <= 1'b0; last_done <= 2'd0;
            force dut.write_req = 1'b0;
            force dut.bmp_load_complete = 1'b0;
            force dut.bmp_load_error = 1'b0;
        end else if (clr_driver) begin
            dst <= D0; dli <= 2'd0; gcnt <= 16'd0;
            have_last <= 1'b0; last_done <= 2'd0;
            ntries = 0;
            for (k=0;k<10;k=k+1) tries[k] = -1;
            force dut.write_req = 1'b0;
            force dut.bmp_load_complete = 1'b0;
            force dut.bmp_load_error = 1'b0;
        end else begin
            case (dst)
                D0: begin
                    force dut.write_req = 1'b0;
                    force dut.bmp_load_complete = 1'b0;
                    if (dut.load_busy && (!have_last || dut.load_idx != last_done)) begin
                        dli <= dut.load_idx;
                        if (ntries < 10) begin tries[ntries] = dut.load_idx; ntries = ntries+1; end
                        dst <= G1;
                    end
                end
                G1: begin force dut.write_req = 1'b1; gcnt <= 16'd0; dst <= G2; end
                G2: begin
                    if (gcnt >= 16'd1) begin force dut.write_req = 1'b0; dst <= G3; end
                    else gcnt <= gcnt + 16'd1;
                end
                G3: begin force dut.bmp_load_complete = 1'b1; dst <= G4; end
                G4: begin force dut.bmp_load_complete = 1'b0; dst <= G5; end
                G5: begin write_finish_toggle <= ~write_finish_toggle; gcnt <= 16'd0; dst <= G6; end
                G6: begin
                    if (gcnt >= 16'd7) dst <= G7;
                    else gcnt <= gcnt + 16'd1;
                end
                G7: if (dut.bank_valid[dli]) begin have_last<=1'b1; last_done<=dli; dst<=D0; end
                default: dst <= D0;
            endcase
        end
    end

    // scan_start_pulse 计数
    reg prev_ssp;
    always @(posedge clk or posedge rst) begin
        if (rst) begin scan_start_cnt <= 0; prev_ssp <= 1'b0; end
        else begin
            if (dut.scan_start_pulse && !prev_ssp) scan_start_cnt <= scan_start_cnt + 1;
            prev_ssp <= dut.scan_start_pulse;
        end
    end

    initial begin clk = 1'b0; forever #5 clk = ~clk; end

    reg _ph, _ar;
    always @(posedge clk) begin
        if (dut.scan_start_pulse || dut.scn_scan_done ||
            (dut.scan_phase !== _ph) || (dut.all_resident !== _ar))
            $display("   M ssp=%b ph:%b->%b sd=%b cnt=%0d dlvl=%b nxt=%0d ar:%b->%b busy=%b",
                dut.scan_start_pulse, _ph, dut.scan_phase, dut.scn_scan_done,
                dut.img_found_count, dut.scan_done_lvl, dut.next_load_idx,
                _ar, dut.all_resident, dut.load_busy);
        _ph <= dut.scan_phase; _ar <= dut.all_resident;
    end

    task reset_dut;
        begin
            rst = 1'b1;
            key_next = 1'b1; key_auto = 1'b1; sw_dir = 1'b0;
            bmp_width = 16'd640; bmp_height = 16'd480;
            write_finish_toggle = 1'b0; write_req_ack = 1'b1; SD_MISO = 1'b1;
            sd_init_force = 1'b0; clr_driver = 1'b0;
            ntries = 0; errors = 0;
            for (k=0;k<10;k=k+1) tries[k] = -1;
            force dut.sd_init_done = 1'b0;
            repeat(6) @(posedge clk);
            rst = 1'b0;
            repeat(4) @(posedge clk);
        end
    endtask

    initial begin
        $display("==== tb_step5_reload start ====");
        reset_dut;
        apply_static_force;

        // ---- 上电：sd_init_done 0->1 ----
        repeat(5) @(posedge clk);
        force dut.sd_init_done = 1'b1; force dut.clear_done_r = 1'b1;

        watchdog = 0;
        while ((dut.all_resident !== 1'b1) && watchdog < 300000) begin
            @(posedge clk); watchdog = watchdog + 1;
        end
        $display("[P1] scan_cnt=%0d ntries=%0d bv=%b ar=%b dv=%b disp=%0d img=%0d",
                  scan_start_cnt, ntries, bank_valid_out, dut.all_resident,
                  display_valid, disp_buf_idx, img_idx_out);
        if (scan_start_cnt !== 1) begin $display("[P1] FAIL scan_start_cnt"); errors=errors+1; end
        if (ntries !== 4) begin $display("[P1] FAIL ntries"); errors=errors+1; end
        if (tries[0]!==0||tries[1]!==1||tries[2]!==2||tries[3]!==3) begin $display("[P1] FAIL seq"); errors=errors+1; end
        if (bank_valid_out !== 4'hF) begin $display("[P1] FAIL bv"); errors=errors+1; end
        if (dut.all_resident !== 1'b1) begin $display("[P1] FAIL ar"); errors=errors+1; end
        if (display_valid !== 1'b1) begin $display("[P1] FAIL dv"); errors=errors+1; end
        if (disp_buf_idx !== 2'd0) begin $display("[P1] FAIL disp"); errors=errors+1; end

        // ---- 拔卡：sd_init_done ->0，保持若干拍 ----
        force dut.sd_init_done = 1'b0;
        repeat(20) @(posedge clk);
        $display("[P2 unplug] bv=%b ar=%b dv=%b disp=%0d scan_kicked=%b",
                  bank_valid_out, dut.all_resident, display_valid, disp_buf_idx, dut.scan_kicked);
        if (display_valid !== 1'b1) begin $display("[P2] FAIL dv held"); errors=errors+1; end
        if (disp_buf_idx !== 2'd0) begin $display("[P2] FAIL disp held"); errors=errors+1; end
        if (bank_valid_out !== 4'h0) begin $display("[P2] FAIL bv cleared"); errors=errors+1; end
        if (dut.all_resident !== 1'b0) begin $display("[P2] FAIL ar cleared"); errors=errors+1; end
        if (dut.scan_kicked !== 1'b0) begin $display("[P2] FAIL scan_kicked cleared"); errors=errors+1; end

        // ---- 重插：清 driver 记录，sd_init_done ->1 ----
        clr_driver = 1'b1;
        @(posedge clk); @(posedge clk);
        clr_driver = 1'b0;
        force dut.sd_init_done = 1'b1; force dut.clear_done_r = 1'b1;

        // 重载期间 display_valid 应出现过 0（扫描+首图）；先等它变0
        watchdog = 0;
        while ((display_valid !== 1'b0) && watchdog < 5000) begin
            @(posedge clk); watchdog = watchdog + 1;
        end
        if (display_valid === 1'b0) $display("[P3] reload black seen (dv=0)");
        else begin $display("[P3] FAIL no reload black"); errors=errors+1; end

        watchdog = 0;
        while ((dut.all_resident !== 1'b1) && watchdog < 300000) begin
            @(posedge clk); watchdog = watchdog + 1;
            if ((watchdog % 3000) == 0)
                $display("   W wd=%0d ready=%b busy=%b nxt=%0d cnt=%0d dst=%0d have=%b clr=%b last=%0d",
                    watchdog, dut.bmp_ready,
                    dut.load_busy, dut.next_load_idx, dut.img_found_count,
                    dst, have_last, clr_driver, last_done);
        end
        $display("[P3 reins] scan_cnt=%0d ntries=%0d bv=%b ar=%b dv=%b disp=%0d img=%0d",
                  scan_start_cnt, ntries, bank_valid_out, dut.all_resident,
                  display_valid, disp_buf_idx, img_idx_out);
        if (scan_start_cnt < 2) begin $display("[P3] FAIL second scan_start"); errors=errors+1; end
        if (ntries !== 4) begin $display("[P3] FAIL ntries"); errors=errors+1; end
        if (tries[0]!==0||tries[1]!==1||tries[2]!==2||tries[3]!==3) begin $display("[P3] FAIL seq"); errors=errors+1; end
        if (bank_valid_out !== 4'hF) begin $display("[P3] FAIL bv"); errors=errors+1; end
        if (dut.all_resident !== 1'b1) begin $display("[P3] FAIL ar"); errors=errors+1; end
        if (display_valid !== 1'b1) begin $display("[P3] FAIL dv restored"); errors=errors+1; end
        if (disp_buf_idx !== 2'd0) begin $display("[P3] FAIL disp"); errors=errors+1; end

        if (errors == 0) $display("==== STEP5 RELOAD ALL PASS ====");
        else $display("==== STEP5 FAIL errors=%0d ====", errors);
        $finish;
    end
endmodule
