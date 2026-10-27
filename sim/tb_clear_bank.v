`timescale 1ns/1ps
// 任务21 步骤5 验证：上电清 4 bank 为黑（背景）
// 行为化 frame_fifo_write/top 的写握手：write_req -> write_req_ack -> 撤销 -> write_en 送数 -> write_finish_toggle
// clear FSM 真实运行，断言 4 个 bank 依次整帧写 0、clear_done 置位。
module tb_clear_bank;
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

    integer errors, k, bankcnt;
    reg [1:0]  rec_buf [0:3];
    reg [20:0] rec_len [0:3];
    reg [31:0] rec_data[0:3];
    reg [15:0] rec_aw[0:3], rec_ah[0:3], rec_ox[0:3], rec_oy[0:3];

    // 模拟 frame_fifo_write 握手
    reg [3:0]  w;
    reg [15:0] wc;

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

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            w <= 4'd0; wc <= 16'd0; write_req_ack <= 1'b0; bankcnt <= 0;
        end else begin
            case (w)
                4'd0: if (write_req) w <= 4'd1;
                4'd1: begin
                    write_req_ack <= 1'b1;
                    if (!write_req) w <= 4'd2;
                end
                4'd2: begin write_req_ack <= 1'b0; w <= 4'd3; end
                4'd3: if (write_en) begin
                    rec_buf[bankcnt] <= write_buf_idx;
                    rec_len[bankcnt] <= write_len;
                    rec_data[bankcnt]<= write_data;
                    rec_aw[bankcnt] <= w_aw; rec_ah[bankcnt] <= w_ah;
                    rec_ox[bankcnt] <= w_aox; rec_oy[bankcnt] <= w_aoy;
                    w <= 4'd4; wc <= 16'd0;
                end
                4'd4: begin
                    if (wc >= 16'd15) begin
                        write_finish_toggle <= ~write_finish_toggle;
                        w <= 4'd5; wc <= 16'd0;
                    end else wc <= wc + 16'd1;
                end
                4'd5: if (!write_en) begin
                    if (bankcnt == 3) w <= 4'd6;
                    else begin bankcnt <= bankcnt + 1; w <= 4'd0; end
                end
                4'd6: w <= 4'd6;
                default: w <= 4'd0;
            endcase
        end
    end

    initial begin clk = 1'b0; forever #5 clk = ~clk; end

    initial begin
        $display("==== tb_clear_bank start ====");
        rst = 1'b1;
        key_next = 1'b1; key_auto = 1'b1; sw_dir = 1'b0;
        bmp_width = 16'd640; bmp_height = 16'd480;
        write_finish_toggle = 1'b0; SD_MISO = 1'b1;
        errors = 0; bankcnt = 0;
        repeat(6) @(posedge clk);
        rst = 1'b0;
        repeat(2) @(posedge clk);
        force dut.sd_init_done = 1'b1;

        // 等 clear 完成（w==6）
        while ((w !== 4'd6) && $time < 200000) @(posedge clk);

        for (k=0;k<4;k=k+1) begin
            $display("[%0d] buf=%0d len=%0d data=%h aw=%0d ah=%0d ox=%0d oy=%0d",
                k, rec_buf[k], rec_len[k], rec_data[k], rec_aw[k], rec_ah[k], rec_ox[k], rec_oy[k]);
        end
        for (k=0;k<4;k=k+1) begin
            if (rec_buf[k] !== k[1:0]) begin $display("FAIL buf[%0d]",k); errors=errors+1; end
            if (rec_len[k] !== 21'd307200) begin $display("FAIL len[%0d]",k); errors=errors+1; end
            if (rec_data[k]!== 32'd0) begin $display("FAIL data[%0d]",k); errors=errors+1; end
            if (rec_aw[k] !== 16'd640 || rec_ah[k] !== 16'd480 ||
                rec_ox[k] !== 16'd0   || rec_oy[k] !== 16'd0) begin
                $display("FAIL geom[%0d]",k); errors=errors+1; end
        end
        if (dut.clear_done_r !== 1'b1) begin $display("FAIL clear_done"); errors=errors+1; end

        if (errors==0) $display("==== CLEAR BANK TESTS PASS ====");
        else $display("==== CLEAR BANK FAIL errors=%0d ====", errors);
        $finish;
    end
endmodule
