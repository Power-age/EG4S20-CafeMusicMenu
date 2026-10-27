`timescale 1ns/1ps
// 任务21 步骤2 验证：顺序装载控制 FSM
// 用 force 把下游(scanner/bmp_read)行为化，驱动 FSM 基于 load_busy 电平逐拍推进。
// 场景A：4 张全好 -> bank_valid=0xF, all_resident=1, 首图(idx0)提交显示
// 场景B：PIC2(idx1)坏 -> 重试一次后跳过, bank_valid=0xD, bad_mask bit1, 首图idx0仍提交
module tb_step2_resident;
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

    integer scenario;
    integer tries[0:9];
    integer ntries;
    integer errors;
    integer watchdog;
    integer k;

    // driver FSM 状态
    reg [4:0] dst;
    localparam D0=5'd0, G1=5'd1, G2=5'd2, G3=5'd3, G4=5'd4,
               G5=5'd5, G6=5'd6, G7=5'd7,
               DB0=5'd10, DB1=5'd11, DB2=5'd12, DB3=5'd13;
    reg [1:0] dli;
    reg [15:0] gcnt;
    reg        have_last;
    reg [1:0]  last_done;

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

    function is_bad;
        input [1:0] li;
        input integer sc;
        begin is_bad = (sc == 2) && (li == 2'd1); end
    endfunction

    task apply_force;
        begin
            force dut.sd_init_done       = 1'b1; force dut.clear_done_r = 1'b1;
            force dut.scan_phase         = 1'b0;
            force dut.scan_done_lvl      = 1'b1;
            force dut.img_found_count    = 3'd4;
            force dut.bmp_ready          = 1'b1;
            force dut.bmp_active_width   = 16'd640;
            force dut.bmp_active_height  = 16'd480;
            force dut.bmp_active_offset_x= 16'd0;
            force dut.bmp_active_offset_y= 16'd0;
            force dut.bmp_active_pixel_count = 21'd307200;
        end
    endtask

    // ---- 下游加载结果驱动 FSM（基于 load_busy 电平）----
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            dst <= D0; gcnt <= 16'd0; dli <= 2'd0;
            have_last <= 1'b0; last_done <= 2'd0;
            force dut.write_req = 1'b0;
            force dut.bmp_load_complete = 1'b0;
            force dut.bmp_load_error = 1'b0;
        end else begin
            case (dst)
                D0: begin
                    force dut.write_req = 1'b0;
                    force dut.bmp_load_complete = 1'b0;
                    force dut.bmp_load_error = 1'b0;
                    if (dut.load_busy && (!have_last || dut.load_idx != last_done)) begin
                        dli <= dut.load_idx;
                        if (ntries < 10) begin tries[ntries] = dut.load_idx; ntries = ntries+1; end
                        dst <= is_bad(dut.load_idx, scenario) ? DB0 : G1;
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
                DB0: begin
                    if (dut.load_retry_used == 1'b0) begin
                        force dut.bmp_load_error = 1'b1; dst <= DB1;
                    end else begin
                        force dut.bmp_load_error = 1'b1; dst <= DB2;
                    end
                end
                DB1: begin
                    force dut.bmp_load_error = 1'b0;
                    if (dut.load_retry_used == 1'b1) dst <= DB0;
                end
                DB2: begin force dut.bmp_load_error = 1'b0; dst <= DB3; end
                DB3: if (dut.bad_image_mask[dli] && !dut.load_busy)
                     begin have_last<=1'b1; last_done<=dli; dst<=D0; end
                default: dst <= D0;
            endcase
        end
    end

    initial begin clk = 1'b0; forever #5 clk = ~clk; end

    reg [4:0] prev_dst;
    always @(posedge clk) begin
        if (dst !== prev_dst)
            $display("  sc=%0d dst=%0d busy=%b nxt=%0d cnt=%0d src=%b wfs=%b wfp=%b tsync=%b tgl=%b comp=%b err=%b retry=%b",
                      scenario, dst, dut.load_busy, dut.next_load_idx, dut.img_found_count,
                      dut.source_done_seen, dut.write_finish_seen, dut.write_finish_pulse,
                      dut.wrfin_tgl_sync, write_finish_toggle,
                      dut.bmp_load_complete, dut.bmp_load_error, dut.load_retry_used);
        prev_dst <= dst;
    end

    task reset_dut;
        begin
            rst = 1'b1;
            key_next = 1'b1; key_auto = 1'b1; sw_dir = 1'b0;
            bmp_width = 16'd640; bmp_height = 16'd480;
            write_finish_toggle = 1'b0; write_req_ack = 1'b1; SD_MISO = 1'b1;
            ntries = 0; errors = 0;
            for (k=0;k<10;k=k+1) tries[k] = -1;
            repeat(6) @(posedge clk);
            rst = 1'b0;
            repeat(4) @(posedge clk);
        end
    endtask

    task release_forces;
        begin
            release dut.sd_init_done; release dut.scan_phase; release dut.scan_done_lvl;
            release dut.img_found_count; release dut.bmp_ready; release dut.bmp_active_width;
            release dut.bmp_active_height; release dut.bmp_active_offset_x;
            release dut.bmp_active_offset_y; release dut.bmp_active_pixel_count;
            release dut.write_req; release dut.bmp_load_complete; release dut.bmp_load_error;
        end
    endtask

    initial begin
        $display("==== tb_step2_resident start ====");

        // ---------- 场景A：全好 ----------
        scenario = 1;
        reset_dut;
        apply_force;
        watchdog = 0;
        while ((dut.all_resident !== 1'b1) && watchdog < 300000) begin
            @(posedge clk); watchdog = watchdog + 1;
        end
        $display("[A] ntries=%0d bank_valid=%b all_res=%b disp_valid=%b disp_buf=%0d img_out=%0d",
                  ntries, bank_valid_out, dut.all_resident, display_valid, disp_buf_idx, img_idx_out);
        if (ntries !== 4) begin $display("[A] FAIL ntries"); errors=errors+1; end
        if (tries[0]!==0||tries[1]!==1||tries[2]!==2||tries[3]!==3) begin $display("[A] FAIL seq"); errors=errors+1; end
        if (bank_valid_out !== 4'hF) begin $display("[A] FAIL bank_valid"); errors=errors+1; end
        if (dut.all_resident !== 1'b1) begin $display("[A] FAIL all_resident"); errors=errors+1; end
        if (display_valid !== 1'b1) begin $display("[A] FAIL display_valid"); errors=errors+1; end
        if (disp_buf_idx !== 2'd0) begin $display("[A] FAIL disp_buf_idx"); errors=errors+1; end
        if (img_idx_out !== 2'd0) begin $display("[A] FAIL img_idx_out"); errors=errors+1; end
        if (errors==0) $display("[A] SCENARIO-A PASS"); else $display("[A] SCENARIO-A FAIL errors=%0d",errors);

        // ---------- 场景B：idx1 坏 ----------
        release_forces;
        scenario = 2; errors = 0;
        reset_dut;
        apply_force;
        watchdog = 0;
        while ((dut.all_resident !== 1'b1) && watchdog < 300000) begin
            @(posedge clk); watchdog = watchdog + 1;
        end
        $display("[B] ntries=%0d bank_valid=%b bad_mask=%b all_res=%b disp_valid=%b disp_buf=%0d img_out=%0d",
                  ntries, bank_valid_out, dut.bad_image_mask, dut.all_resident,
                  display_valid, disp_buf_idx, img_idx_out);
        if (ntries !== 4) begin $display("[B] FAIL ntries"); errors=errors+1; end
        if (tries[0]!==0||tries[1]!==1||tries[2]!==2||tries[3]!==3) begin $display("[B] FAIL seq"); errors=errors+1; end
        if (bank_valid_out !== 4'hD) begin $display("[B] FAIL bank_valid"); errors=errors+1; end
        if (dut.bad_image_mask !== 4'b0010) begin $display("[B] FAIL bad_mask"); errors=errors+1; end
        if (dut.all_resident !== 1'b1) begin $display("[B] FAIL all_resident"); errors=errors+1; end
        if (display_valid !== 1'b1) begin $display("[B] FAIL display_valid"); errors=errors+1; end
        if (disp_buf_idx !== 2'd0) begin $display("[B] FAIL disp_buf_idx"); errors=errors+1; end
        if (img_idx_out !== 2'd0) begin $display("[B] FAIL img_idx_out"); errors=errors+1; end
        if (errors==0) $display("[B] SCENARIO-B PASS"); else $display("[B] SCENARIO-B FAIL errors=%0d",errors);

        $display("==== tb_step2_resident done ====");
        $finish;
    end
endmodule
