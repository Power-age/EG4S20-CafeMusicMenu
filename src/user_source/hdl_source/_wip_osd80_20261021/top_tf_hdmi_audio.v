
module top(
    input                       clk,
    input                       rst_n,
    input                       key1,           // 手动下一张
    input                       key2,           // 自动播放 开/关
    input                       key3,
    input                       sw_con0,
    input                       sw_con1,
    input                       sw_key_mode,    // 拨到ON(=0)=音量模式, 未拨(=1)=切图模式
    input                       sw_transition,

    output [7:0]                seg_sel,
    output [7:0]                seg_data,

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso
);

parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter FRAME_PIXELS  = 24'd307200;   // 640*480
parameter BANK0_ADDR    = 24'd0;
parameter BANK1_ADDR    = FRAME_PIXELS;
parameter BANK2_ADDR    = FRAME_PIXELS*24'd2;
parameter BANK3_ADDR    = FRAME_PIXELS*24'd3;
localparam [1:0] E2_FADE_IDLE = 2'd0;
localparam [1:0] E2_FADE_OUT  = 2'd1;
localparam [1:0] E2_FADE_IN   = 2'd2;
localparam [3:0] E2_FADE_HOLD_FRAMES = 4'd6;
localparam [3:0] E2_FADE_HOLD_LAST   = E2_FADE_HOLD_FRAMES - 4'd1;

wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_card_clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire hs;
wire vs;
wire de;

wire [23:0] vout_data_raw;
wire [23:0] vout_data_base;
wire [23:0] vout_data_wave;
wire [23:0] vout_data;
wire [23:0] vout_data_pre;
wire        wave_vs;
wire        wave_de;
wire        osd_vs;
wire        osd_de;
wire        osd_rd_en;
wire [7:0]  osd_rd_x;
wire [6:0]  osd_rd_y;
wire [1:0]  osd_rd_data;
wire        wave_wr_en;
wire [9:0]  wave_wr_addr;
wire [7:0]  wave_wr_data;
wire        wave_block_done;
wire        wave_rd_en;
wire [9:0]  wave_rd_addr;
wire [7:0]  wave_rd_data;
wire        wave_rd_valid;
wire        wave_block_accept;
wire        wave_front_valid;
wire        wave_front_sel;
wire        osd_font_rd_en;
wire [6:0]  osd_font_ascii;
wire [2:0]  osd_font_row;
wire [7:0]  osd_font_rd_data;
wire        osd_font_rd_valid;
wire        osd_buf_wr_en;
wire [7:0]  osd_buf_wr_x;
wire [6:0]  osd_buf_wr_y;
wire [1:0]  osd_buf_wr_data;
wire        osd_req_ready;
wire        osd_busy;
wire [79:0] osd_dirty_row;
wire        sb_req_valid;
wire [6:0]  sb_req_ascii;
wire [7:0]  sb_req_x;
wire [6:0]  sb_req_y;
wire [1:0]  sb_req_type;
wire [3:0]  cur_track_idx_sd;
wire [87:0] cur_track_name_sd;
reg  [3:0]  tki_meta, tki_sync;
reg  [87:0] tkn_meta, tkn_sync;
reg  [3:0]  volv_meta, volv_sync;
wire [2:0]  ui_alpha;
wire        display_valid;
wire        display_valid_video;
wire [15:0] display_active_width_sd;
wire [15:0] display_active_height_sd;
wire [15:0] display_active_offset_x_sd;
wire [15:0] display_active_offset_y_sd;
wire        display_image_area;
wire [15:0] video_x_pos;
wire [15:0] video_y_pos;
wire [15:0] display_active_right;
wire [15:0] display_active_bottom;
wire        transition_fade_mode;
wire        transition_busy_video;
wire        key1_to_sd;
wire [1:0]  frame_read_buf_idx;
wire        osd_auto_play_en;
wire        key3_trig;
reg  [1:0]  brightness_level;
reg  [1:0]  contrast_level;
wire        param_default_en;
// 任务18：按键模式（sw_key_mode：拨到ON=音量 / 未拨=切图）
wire        vol_mode_raw;
wire        vol_mode_a, vol_mode_sd, vol_mode_v, vol_mode_c;
wire        key1_to_video, key2_to_sd;
wire        k1_short_v, k2_short_v;
wire        k1_long_v, k2_long_v;
wire        k1_long_active_v, k2_long_active_v;
reg         track_cmd_req_v;
reg  [1:0]  track_cmd_data_v;
reg         track_cmd_pending_v;
reg         track_cmd_ack_v1, track_cmd_ack_v2;
reg         track_cmd_req_sd1, track_cmd_req_sd2, track_cmd_req_seen_sd;
reg  [1:0]  track_cmd_data_sd1, track_cmd_data_sd2;
reg         track_cmd_ack_sd;
reg         track_cmd_prev_sd;
reg         track_cmd_next_sd;
reg         transition_busy_sd_meta;
reg         transition_busy_sd_sync;
reg  [1:0]  e2_disp_buf_meta;
reg  [1:0]  e2_disp_buf_sync;
reg  [1:0]  e2_disp_buf_prev;
reg         e2_display_valid_meta;
reg         e2_display_valid_sync;
reg         e2_transition_mode_meta;
reg         e2_transition_mode_sync;
reg         e2_vs_d;
reg         e2_transition_pending;
reg         e2_transition_active;
reg  [9:0]  e2_transition_reveal_x;
reg  [1:0]  e2_fade_state;
reg  [2:0]  e2_fade_level;
reg  [3:0]  e2_fade_hold_cnt;
reg  [1:0]  e2_fade_read_buf_idx;
reg  [1:0]  e2_fade_target_buf_idx;
reg  [15:0] e2_active_width_meta;
reg  [15:0] e2_active_width_sync;
reg  [15:0] e2_active_height_meta;
reg  [15:0] e2_active_height_sync;
reg  [15:0] e2_active_offset_x_meta;
reg  [15:0] e2_active_offset_x_sync;
reg  [15:0] e2_active_offset_y_meta;
reg  [15:0] e2_active_offset_y_sync;
reg  [15:0] e2_display_width_reg;
reg  [15:0] e2_display_height_reg;
reg  [15:0] e2_display_offset_x_reg;
reg  [15:0] e2_display_offset_y_reg;
reg  [10:0] video_x_cnt;
reg  [9:0]  video_y_cnt;
reg         video_de_d;
reg         video_vs_d;
wire        e2_frame_pulse;
wire        e2_disp_changed;
wire        e2_fade_hold_done;

wire [3:0]  state_code;
wire [3:0]  hang_dbg;
wire [6:0]  seg_data_0;
wire [6:0]  seg_data_img;
wire [6:0]  seg_data_hang;
wire [6:0]  seg_data_bank;
wire [6:0]  seg_data_vol;
reg [3:0]   vol_lvl_c1, vol_lvl_c2;
wire [3:0]  bank_valid_wire;
wire [1:0]  img_idx_wire;

// 任务21 步骤3：常驻帧消隐硬切（video_clk 域）
wire        all_resident_wire;        // sd_card_clk 域原始
reg  [3:0]  bv_meta, bv_sync;         // bank_valid -> video
reg         ar_meta, ar_sync;         // all_resident -> video
reg         ape_meta, ape_sync;       // osd_auto_play_en -> video
reg         swd_meta, swd_sync;       // sw_con1(dir) -> video
wire        key1_video_pulse;         // key1 在 video 域消抖
wire [1:0]  resident_target;          // 常驻挂起目标（转场映射）
wire [3:0]  img_num_display;

wire        video_read_req;
wire        video_read_req_ack;
wire        video_read_en;
wire [31:0] video_read_data;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire [20:0] sd_card_write_len;
wire [15:0] sd_card_write_active_width;
wire [15:0] sd_card_write_active_height;
wire [15:0] sd_card_write_active_offset_x;
wire [15:0] sd_card_write_active_offset_y;
wire        frame_write_finish;
reg         frame_write_toggle_mem;

wire [1:0]  write_buf_idx;
wire [1:0]  disp_buf_idx;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;

// HDMI 1.4b 音频发射相关
wire        audio_pll_lock;
wire        sys_pll_lock;
wire        video_pll_lock;
wire        audio_mclk;
wire        audio_i2s_bclk;
wire        audio_i2s_lrck;
wire        audio_i2s_dout;
wire        audio_valid;
wire [23:0] audio_left_data;
wire [23:0] audio_right_data;

// WAV 播放器（sd_card_bmp 内）与音源 mux
wire [15:0] wav_pcm_wire;
wire        wav_playing_wire;          // sd_card_clk 域
reg         wav_play_v1, wav_play_v2;
wire [23:0] wav_pcm24;
wire [23:0] hdmi_audio_left, hdmi_audio_right;

wire        acr_valid;
wire [19:0] acr_cts;
wire [19:0] acr_n;

wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

// 统一复位：TF 图像链路 + HDMI 音频链路
wire rst_all;

assign rst_all = ~rst_n | ~audio_pll_lock | ~sys_pll_lock | ~video_pll_lock;
assign param_default_en = 1'b0;   // 任务18：原 sw_default 已改为按键模式选择，取消一键默认
assign vol_mode_raw = ~sw_key_mode;   // 拨到ON(0) -> 音量模式
assign transition_fade_mode = ~sw_transition;
assign transition_busy_video = e2_transition_mode_sync && (e2_fade_state != E2_FADE_IDLE);
assign key1_to_sd = (vol_mode_sd || transition_busy_sd_sync) ? 1'b1 : key1;
assign key2_to_sd = vol_mode_sd ? 1'b1 : key2;
assign key1_to_video = vol_mode_v ? 1'b1 : key1;
// fade：黑场点切；reveal 常驻取目标 sync；首图阶段取 disp_buf
assign frame_read_buf_idx =
      e2_transition_mode_sync ? e2_fade_read_buf_idx :
      ar_sync                 ? e2_disp_buf_sync :
                                disp_buf_idx;
assign e2_frame_pulse = e2_vs_d && !vs;
assign e2_disp_changed = e2_display_valid_sync && (e2_disp_buf_sync != e2_disp_buf_prev);
assign e2_fade_hold_done = (e2_fade_hold_cnt >= E2_FADE_HOLD_LAST);
assign display_valid_video = e2_display_valid_sync;
assign video_x_pos = {5'd0, video_x_cnt};
assign video_y_pos = {6'd0, video_y_cnt};
assign display_active_right = e2_display_offset_x_reg + e2_display_width_reg;
assign display_active_bottom = e2_display_offset_y_reg + e2_display_height_reg;
assign display_image_area = display_valid_video && de &&
                            (video_x_pos >= e2_display_offset_x_reg) &&
                            (video_x_pos < display_active_right) &&
                            (video_y_pos >= e2_display_offset_y_reg) &&
                            (video_y_pos < display_active_bottom);
key_press_debounce #(
    .CLK_FREQ_HZ      (25_000_000),
    .DEBOUNCE_MS      (20)
) key_press_debounce_brightness(
    .clk              (video_clk),
    .rst              (rst_all),
    .button_in        (key3),
    .press_pulse      (key3_trig)
);

always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        brightness_level <= 2'd0;
        contrast_level   <= 2'd0;
    end
    else if (key3_trig) begin
        if (sw_con0)
            contrast_level   <= contrast_level + 2'd1;
        else
            brightness_level <= brightness_level + 2'd1;
    end
end

always @(posedge sd_card_clk or posedge rst_all) begin
    if (rst_all) begin
        transition_busy_sd_meta <= 1'b0;
        transition_busy_sd_sync <= 1'b0;
    end
    else begin
        transition_busy_sd_meta <= transition_busy_video;
        transition_busy_sd_sync <= transition_busy_sd_meta;
    end
end

always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        e2_disp_buf_meta <= 2'd0;
        e2_disp_buf_sync <= 2'd0;
        e2_disp_buf_prev <= 2'd0;
        e2_display_valid_meta <= 1'b0;
        e2_display_valid_sync <= 1'b0;
        e2_transition_mode_meta <= 1'b0;
        e2_transition_mode_sync <= 1'b0;
        e2_vs_d <= 1'b0;
        e2_transition_pending <= 1'b0;
        e2_transition_active <= 1'b0;
        e2_transition_reveal_x <= 10'd640;
        e2_fade_state <= E2_FADE_IDLE;
        e2_fade_level <= 3'd0;
        e2_fade_hold_cnt <= 4'd0;
        e2_fade_read_buf_idx <= 2'd0;
        e2_fade_target_buf_idx <= 2'd0;
        e2_active_width_meta <= 16'd640;
        e2_active_width_sync <= 16'd640;
        e2_active_height_meta <= 16'd480;
        e2_active_height_sync <= 16'd480;
        e2_active_offset_x_meta <= 16'd0;
        e2_active_offset_x_sync <= 16'd0;
        e2_active_offset_y_meta <= 16'd0;
        e2_active_offset_y_sync <= 16'd0;
        e2_display_width_reg <= 16'd640;
        e2_display_height_reg <= 16'd480;
        e2_display_offset_x_reg <= 16'd0;
        e2_display_offset_y_reg <= 16'd0;
    end
    else begin
        e2_disp_buf_meta <= ar_sync ? resident_target : disp_buf_idx;
        e2_disp_buf_sync <= e2_disp_buf_meta;
        e2_display_valid_meta <= display_valid;
        e2_display_valid_sync <= e2_display_valid_meta;
        e2_transition_mode_meta <= transition_fade_mode;
        e2_transition_mode_sync <= e2_transition_mode_meta;
        e2_active_width_meta <= display_active_width_sd;
        e2_active_width_sync <= e2_active_width_meta;
        e2_active_height_meta <= display_active_height_sd;
        e2_active_height_sync <= e2_active_height_meta;
        e2_active_offset_x_meta <= display_active_offset_x_sd;
        e2_active_offset_x_sync <= e2_active_offset_x_meta;
        e2_active_offset_y_meta <= display_active_offset_y_sd;
        e2_active_offset_y_sync <= e2_active_offset_y_meta;
        e2_vs_d <= vs;

        if (!e2_transition_mode_sync) begin
            e2_fade_state <= E2_FADE_IDLE;
            e2_fade_level <= 3'd0;
            e2_fade_hold_cnt <= 4'd0;
            e2_fade_read_buf_idx <= e2_disp_buf_sync;
            e2_fade_target_buf_idx <= e2_disp_buf_sync;
            e2_display_width_reg <= e2_active_width_sync;
            e2_display_height_reg <= e2_active_height_sync;
            e2_display_offset_x_reg <= e2_active_offset_x_sync;
            e2_display_offset_y_reg <= e2_active_offset_y_sync;

            if (e2_disp_changed) begin
                e2_transition_pending <= 1'b1;
            end
            else if (e2_transition_active && e2_frame_pulse) begin
                if (e2_transition_reveal_x >= 10'd620) begin
                    e2_transition_active <= 1'b0;
                    e2_transition_reveal_x <= 10'd640;
                end
                else begin
                    e2_transition_reveal_x <= e2_transition_reveal_x + 10'd20;
                end
            end
            else if (e2_transition_pending && e2_frame_pulse) begin
                e2_transition_pending <= 1'b0;
                e2_transition_active <= 1'b1;
                e2_transition_reveal_x <= 10'd20;
            end
        end
        else begin
            e2_transition_pending <= 1'b0;
            e2_transition_active <= 1'b0;
            e2_transition_reveal_x <= 10'd640;

            case (e2_fade_state)
                E2_FADE_IDLE: begin
                    e2_fade_level <= 3'd0;
                    e2_fade_hold_cnt <= 4'd0;
                    if (e2_disp_changed) begin
                        e2_fade_state <= E2_FADE_OUT;
                        e2_fade_target_buf_idx <= e2_disp_buf_sync;
                    end
                    else begin
                        e2_fade_read_buf_idx <= e2_disp_buf_sync;
                        e2_fade_target_buf_idx <= e2_disp_buf_sync;
                        e2_display_width_reg <= e2_active_width_sync;
                        e2_display_height_reg <= e2_active_height_sync;
                        e2_display_offset_x_reg <= e2_active_offset_x_sync;
                        e2_display_offset_y_reg <= e2_active_offset_y_sync;
                    end
                end
                E2_FADE_OUT: begin
                    if (e2_disp_changed)
                        e2_fade_target_buf_idx <= e2_disp_buf_sync;
                    if (e2_frame_pulse) begin
                        if (e2_fade_hold_done) begin
                            e2_fade_hold_cnt <= 4'd0;
                            if (e2_fade_level >= 3'd4) begin
                                e2_fade_state <= E2_FADE_IN;
                                e2_fade_read_buf_idx <= e2_disp_changed ? e2_disp_buf_sync : e2_fade_target_buf_idx;
                                e2_display_width_reg <= e2_active_width_sync;
                                e2_display_height_reg <= e2_active_height_sync;
                                e2_display_offset_x_reg <= e2_active_offset_x_sync;
                                e2_display_offset_y_reg <= e2_active_offset_y_sync;
                            end
                            else begin
                                e2_fade_level <= e2_fade_level + 3'd1;
                            end
                        end
                        else begin
                            e2_fade_hold_cnt <= e2_fade_hold_cnt + 4'd1;
                        end
                    end
                end
                E2_FADE_IN: begin
                    if (e2_disp_changed) begin
                        e2_fade_state <= E2_FADE_OUT;
                        e2_fade_hold_cnt <= 4'd0;
                        e2_fade_target_buf_idx <= e2_disp_buf_sync;
                    end
                    else if (e2_frame_pulse) begin
                        if (e2_fade_hold_done) begin
                            e2_fade_hold_cnt <= 4'd0;
                            if (e2_fade_level == 3'd0) begin
                                e2_fade_state <= E2_FADE_IDLE;
                                e2_fade_read_buf_idx <= e2_disp_buf_sync;
                                e2_fade_target_buf_idx <= e2_disp_buf_sync;
                                e2_display_width_reg <= e2_active_width_sync;
                                e2_display_height_reg <= e2_active_height_sync;
                                e2_display_offset_x_reg <= e2_active_offset_x_sync;
                                e2_display_offset_y_reg <= e2_active_offset_y_sync;
                            end
                            else begin
                                e2_fade_level <= e2_fade_level - 3'd1;
                            end
                        end
                        else begin
                            e2_fade_hold_cnt <= e2_fade_hold_cnt + 4'd1;
                        end
                    end
                end
                default: begin
                    e2_fade_state <= E2_FADE_IDLE;
                    e2_fade_level <= 3'd0;
                    e2_fade_hold_cnt <= 4'd0;
                    e2_fade_read_buf_idx <= e2_disp_buf_sync;
                    e2_fade_target_buf_idx <= e2_disp_buf_sync;
                    e2_display_width_reg <= e2_active_width_sync;
                    e2_display_height_reg <= e2_active_height_sync;
                    e2_display_offset_x_reg <= e2_active_offset_x_sync;
                    e2_display_offset_y_reg <= e2_active_offset_y_sync;
                end
            endcase
        end

        e2_disp_buf_prev <= e2_disp_buf_sync;
    end
end

// ---- 任务21 步骤3：key1 在 video_clk 域消抖 ----
key_press_debounce #(
    .CLK_FREQ_HZ      (25_000_000),
    .DEBOUNCE_MS      (20)
) key_press_debounce_resident(
    .clk              (video_clk),
    .rst              (rst_all),
    .button_in        (key1_to_video),
    .press_pulse      (key1_video_pulse)
);

// ---- sd_card_clk 域状态信号同步到 video_clk 域 ----
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        bv_meta  <= 4'd0;  bv_sync  <= 4'd0;
        ar_meta  <= 1'b0;  ar_sync  <= 1'b0;
        ape_meta <= 1'b0;  ape_sync <= 1'b0;
        swd_meta <= 1'b0;  swd_sync <= 1'b0;
        tki_meta <= 4'd0;  tki_sync <= 4'd0;
        tkn_meta <= 88'd0; tkn_sync <= 88'd0;
        volv_meta<= 4'd0;  volv_sync<= 4'd0;
    end
    else begin
        bv_meta  <= bank_valid_wire;   bv_sync  <= bv_meta;
        ar_meta  <= all_resident_wire; ar_sync  <= ar_meta;
        ape_meta <= osd_auto_play_en;  ape_sync <= ape_meta;
        swd_meta <= sw_con1;           swd_sync <= swd_meta;
        tki_meta <= cur_track_idx_sd;  tki_sync <= tki_meta;
        tkn_meta <= cur_track_name_sd; tkn_sync <= tkn_meta;
        volv_meta<= vol_lvl_c2;        volv_sync<= volv_meta;
    end
end

// ---- 常驻帧消隐硬切 ----
resident_switch #(
    .AUTO_TICKS       (25_000_000)
) resident_switch_m0(
    .clk              (video_clk),
    .rst              (rst_all),
    .frame_pulse      (e2_frame_pulse),
    .key_pulse        (key1_video_pulse),
    .auto_en          (ape_sync),
    .bank_valid       (bv_sync),
    .all_resident     (ar_sync),
    .cur_disp         (e2_disp_buf_sync),
    .dir              (swd_sync),
    .resident_idx     (),             // 转场模式：硬切输出悬空
    .target_out       (resident_target)
);

always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        video_x_cnt <= 11'd0;
        video_y_cnt <= 10'd0;
        video_de_d <= 1'b0;
        video_vs_d <= 1'b0;
    end
    else begin
        video_de_d <= de;
        video_vs_d <= vs;

        if (video_vs_d != vs) begin
            video_x_cnt <= 11'd0;
            video_y_cnt <= 10'd0;
        end
        else if (de) begin
            video_x_cnt <= video_x_cnt + 11'd1;
        end
        else begin
            video_x_cnt <= 11'd0;
            if (video_de_d)
                video_y_cnt <= video_y_cnt + 10'd1;
        end
    end
end

// 保持你原来的 TF / SDRAM / video 时钟
sys_pll sys_pll_m0(
    .refclk     (clk),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft),
    .lock_out   (sys_pll_lock),
    .reset      (1'b0)
);

video_pll video_pll_m0(
    .refclk     (clk),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk),
    .lock_out   (video_pll_lock),
    .reset      (1'b0)
);

// 复用你 I2S->HDMI 工程里的 PLL，只取 12.288MHz 音频主时钟
PLL_HDMI_AUDIO u_audio_pll(
    .refclk     (clk),
    .reset      (1'b0),
    .extlock    (audio_pll_lock),
    .clk0_out   (),
    .clk1_out   (),
    .clk2_out   (audio_mclk)
);

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or posedge rst_all) begin
    if (rst_all)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// ===================== TF 多图扫描与缓存（双缓冲） =====================
sd_card_bmp #(
    .CLK_FREQ_HZ       (100_000_000),
    .SCAN_START_SECTOR (32'd0),
    .SCAN_MAX_SECTOR   (32'd131071),
    .SCAN_TARGET_COUNT (3'd4)
) sd_card_bmp_m0(
    .clk               (sd_card_clk),
    .rst               (rst_all),
    .key_next          (key1_to_sd),
    .key_auto          (key2_to_sd),
    .state_code        (state_code),
    .hang_dbg          (hang_dbg),
    .bank_valid_out    (bank_valid_wire),
    .all_resident_out  (all_resident_wire),
    .bmp_width         (16'd640),
    .bmp_height        (16'd480),
    .display_valid     (display_valid),
    .osd_auto_play_en  (osd_auto_play_en),
    .display_active_width(display_active_width_sd),
    .display_active_height(display_active_height_sd),
    .display_active_offset_x(display_active_offset_x_sd),
    .display_active_offset_y(display_active_offset_y_sd),

    .write_finish_toggle(frame_write_toggle_mem),
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (disp_buf_idx),

    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_len         (sd_card_write_len),
    .write_active_width(sd_card_write_active_width),
    .write_active_height(sd_card_write_active_height),
    .write_active_offset_x(sd_card_write_active_offset_x),
    .write_active_offset_y(sd_card_write_active_offset_y),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .SD_nCS            (sd_ncs),
    .SD_DCLK           (sd_dclk),
    .SD_MOSI           (sd_mosi),
    .SD_MISO           (sd_miso),
    .img_idx_out       (img_idx_wire),
    .sw_dir            (sw_con1),
    .audio_mclk        (audio_mclk),
    .video_clk         (video_clk),
    .audio_tick        (audio_valid),
    .track_cmd_prev    (track_cmd_prev_sd),
    .track_cmd_next    (track_cmd_next_sd),
    .wav_pcm           (wav_pcm_wire),
    .wav_pcm_valid     (),
    .wav_playing       (wav_playing_wire),
    .cur_track_index   (cur_track_idx_sd),
    .cur_track_name    (cur_track_name_sd)
);

seg_decoder seg_decoder_m0(
    .bin_data          (state_code),
    .seg_data          (seg_data_0)
);

seg_decoder seg_decoder_img(
    .bin_data          (img_num_display),
    .seg_data          (seg_data_img)
);

seg_decoder seg_decoder_hang(
    .bin_data          (hang_dbg),
    .seg_data          (seg_data_hang)
);

seg_decoder seg_decoder_bank(
    .bin_data          (bank_valid_wire),
    .seg_data          (seg_data_bank)
);

assign img_num_display = ar_sync ? ({2'd0, e2_disp_buf_sync} + 4'd1)
                         : ({2'd0, img_idx_wire} + 4'd1);

seg_scan seg_scan_m0(
    .clk               (clk),
    .rst_n             (rst_n),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),
    .seg_data_0        ({1'b1,7'b1111_111}),
    .seg_data_1        ({1'b1,7'b1111_111}),
    .seg_data_2        ({1'b1,seg_data_vol}),
    .seg_data_3        ({1'b1,seg_data_img}),
    .seg_data_4        ({1'b1,seg_data_bank}),
    .seg_data_5        ({1'b1,seg_data_0}),
    .seg_data_6        ((hang_dbg == 4'd0) ? {1'b1,7'b1111_111} : {1'b1,seg_data_hang}),
    .seg_data_7        ({1'b1,7'b1111_111})
);

// ===================== 原图像时序与帧缓存 =====================
video_timing_data video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);

video_delay video_delay_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_en           (video_read_en),
    .read_data         (video_read_data[31:8]),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .hs_r              (hs),
    .vs_r              (vs),
    .de_r              (de),
    .vout_data         (vout_data_raw)
);

// 首图提交前黑屏；提交后一直显示当前显示缓冲区内容
assign vout_data_base = display_image_area ? vout_data_raw : 24'd0;

waveform_render u_waveform_render (
    .I_clk          (video_clk),
    .I_rst          (rst_all),
    .I_vs           (vs),
    .I_de           (de),
    .I_x            (video_x_cnt[9:0]),
    .I_y            (video_y_cnt),
    .I_rgb          (vout_data_base),
    .O_vs           (wave_vs),
    .O_de           (wave_de),
    .O_rgb          (vout_data_wave),
    .O_wave_rd_en   (wave_rd_en),
    .O_wave_rd_addr (wave_rd_addr),
    .I_wave_rd_data (wave_rd_data),
    .I_wave_rd_valid(wave_rd_valid)
);

osd_renderer u_osd_renderer (
    .clk(video_clk), .rst(rst_all), .vs(vs), .de(de),
    .req_valid(sb_req_valid),
    .req_ascii(sb_req_ascii),
    .req_x(sb_req_x),
    .req_y(sb_req_y),
    .req_type(sb_req_type),
    .req_ready(osd_req_ready),
    .font_rd_en(osd_font_rd_en),
    .font_ascii(osd_font_ascii),
    .font_row(osd_font_row),
    .font_rd_data(osd_font_rd_data),
    .font_rd_valid(osd_font_rd_valid),
    .buf_wr_en(osd_buf_wr_en),
    .buf_wr_x(osd_buf_wr_x),
    .buf_wr_y(osd_buf_wr_y),
    .buf_wr_data(osd_buf_wr_data),
    .dirty_clr(1'b0),
    .busy(osd_busy),
    .dirty_row(osd_dirty_row)
);

font_rom u_font_rom (
    .clk(video_clk), .rst(rst_all),
    .rd_en(osd_font_rd_en),
    .ascii(osd_font_ascii),
    .row(osd_font_row),
    .rd_data(osd_font_rd_data),
    .rd_valid(osd_font_rd_valid)
);

osd_buffer u_osd_buffer (
    .clk(video_clk), .rst(rst_all),
    .wr_en(osd_buf_wr_en),
    .wr_x(osd_buf_wr_x),
    .wr_y(osd_buf_wr_y),
    .wr_data(osd_buf_wr_data),
    .rd_en(osd_rd_en),
    .rd_x(osd_rd_x),
    .rd_y(osd_rd_y),
    .rd_data(osd_rd_data),
    .rd_valid()
);

osd_buffer_overlay u_osd_buffer_overlay (
    .I_clk  (video_clk),
    .I_rst  (rst_all),
    .I_vs   (wave_vs),
    .I_de   (wave_de),
    .I_rgb  (vout_data_pre),
    .I_ui_alpha(ui_alpha),
    .I_panel_vis(1'b0),          // 2026/10/21 18:5x 暂时关闭：面板版 WNS −3049 导致帧写卡死（数码管报 b），先恢复可用版本
    .O_vs   (osd_vs),
    .O_de   (osd_de),
    .O_rgb  (vout_data),
    .rd_en  (osd_rd_en),
    .rd_x   (osd_rd_x),
    .rd_y   (osd_rd_y),
    .rd_data(osd_rd_data)
);

ui_visible_ctl u_ui_visible_ctl (
    .clk              (video_clk),
    .rst              (rst_all),
    .vs               (wave_vs),
    .track_name       (tkn_sync),
    .vol_level        (volv_sync),
    .img_idx          (e2_disp_buf_sync),
    .auto_en          (ape_sync),
    .brightness_level (brightness_level),
    .contrast_level   (contrast_level),
    .state_code       (state_code),
    .ui_alpha         (ui_alpha)
);

status_bar_render u_status_bar_render (
    .clk        (video_clk),
    .rst        (rst_all),
    .vs         (vs),
    .track_name (tkn_sync),
    .vol_level  (volv_sync),
    .img_idx    (e2_disp_buf_sync),
    .auto_en    (ape_sync),
    .req_valid  (sb_req_valid),
    .req_ascii  (sb_req_ascii),
    .req_x      (sb_req_x),
    .req_y      (sb_req_y),
    .req_type   (sb_req_type),
    .req_ready  (osd_req_ready)
);

video_osd_overlay u_video_osd_overlay(
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_enable      (display_valid_video),
    .I_vs          (wave_vs),
    .I_de          (wave_de),
    .I_rgb         (vout_data_wave),
    .I_state_code  (state_code),
    .I_auto_play_en(osd_auto_play_en),
    .I_brightness_level(brightness_level),
    .I_contrast_level(contrast_level),
    .I_param_default_en(param_default_en),
    .I_transition_active(e2_transition_active),
    .I_transition_reveal_x(e2_transition_reveal_x),
    .I_fade_level  (e2_fade_level),
    .O_rgb         (vout_data_pre)
);

frame_read_write #(
    .WRITE_V_FLIP     (1),
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (480)
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (),
    .read_addr_0       (BANK0_ADDR),
    .read_addr_1       (BANK1_ADDR),
    .read_addr_2       (BANK2_ADDR),
    .read_addr_3       (BANK3_ADDR),
    .read_addr_index   (frame_read_buf_idx),
    .read_len          (FRAME_PIXELS),
    .read_en           (video_read_en),
    .read_data         (video_read_data),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BANK0_ADDR),
    .write_addr_1      (BANK1_ADDR),
    .write_addr_2      (BANK2_ADDR),
    .write_addr_3      (BANK3_ADDR),
    .write_addr_index  (write_buf_idx),
    .write_len         (sd_card_write_len),
    .write_active_width(sd_card_write_active_width),
    .write_active_height(sd_card_write_active_height),
    .write_active_offset_x(sd_card_write_active_offset_x),
    .write_active_offset_y(sd_card_write_active_offset_y),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (rst_all),
    .App_ref_allow     (all_resident_wire),
    .frame_tick        (e2_frame_pulse),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

// ===================== 音频：内部 I2S 测试音 =====================
hdmi_audio_tone_i2s_64fs #(
    .PHASE_INC (32'd39370534),
    .AMP       (24'sd2000000)
) u_hdmi_audio_tone_i2s_64fs (
    .I_mclk      (audio_mclk),
    .I_rst       (rst_all),
    .O_i2s_BCLK  (audio_i2s_bclk),
    .O_i2s_LRCK  (audio_i2s_lrck),
    .O_i2s_DOUT  (audio_i2s_dout)
);

I2S_receiver u_I2S_receiver(
    .I_clk              (video_clk),
    .I_rst              (rst_all),
    .I_i2s_BCLK         (audio_i2s_bclk),
    .I_i2s_LRCK         (audio_i2s_lrck),
    .I_i2s_DOUT         (audio_i2s_dout),
    .O_audio_valid      (audio_valid),
    .O_audio_left_data  (audio_left_data),
    .O_audio_right_data (audio_right_data)
);

// ---- 音源 mux：WAV 播放中选 WAV(16→24bit)，否则选测试音 ----
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        wav_play_v1 <= 1'b0;
        wav_play_v2 <= 1'b0;
    end else begin
        wav_play_v1 <= wav_playing_wire;
        wav_play_v2 <= wav_play_v1;
    end
end
assign wav_pcm24        = {wav_pcm_wire[15:0], 8'b0};
assign hdmi_audio_left  = wav_play_v2 ? wav_pcm24 : audio_left_data;
assign hdmi_audio_right = wav_play_v2 ? wav_pcm24 : audio_right_data;

// ===================== 任务 18：数字音量调节（拨码切模式，短按一下一档）=====================
wire [3:0]  vol_level_a;
wire signed [23:0] vol_audio_l, vol_audio_r;

// key1/key2 在 audio 域消抖，取按下确认短脉冲（低有效按键 -> button_negedge）
key_longshort #(.CLOCK_MHZ(25), .LONG_CYCLES(15_000_000), .REPEAT_CYCLES(3_000_000), .REPEAT_ENABLE(0)) u_key1_longshort (
    .clk(video_clk), .rst_n(~rst_all), .button_in(key1),
    .short_pulse(k1_short_v), .long_repeat(k1_long_v), .long_active(k1_long_active_v)
);
key_longshort #(.CLOCK_MHZ(25), .LONG_CYCLES(15_000_000), .REPEAT_CYCLES(3_000_000), .REPEAT_ENABLE(0)) u_key2_longshort (
    .clk(video_clk), .rst_n(~rst_all), .button_in(key2),
    .short_pulse(k2_short_v), .long_repeat(k2_long_v), .long_active(k2_long_active_v)
);

// 音量模式：key2 加 / key1 减（短按一下一档）
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        track_cmd_req_v <= 1'b0;
        track_cmd_data_v <= 2'd0;
        track_cmd_pending_v <= 1'b0;
        track_cmd_ack_v1 <= 1'b0;
        track_cmd_ack_v2 <= 1'b0;
    end else begin
        track_cmd_ack_v1 <= track_cmd_ack_sd;
        track_cmd_ack_v2 <= track_cmd_ack_v1;
        if (track_cmd_pending_v && track_cmd_ack_v2 == track_cmd_req_v)
            track_cmd_pending_v <= 1'b0;
        if (vol_mode_v && !track_cmd_pending_v) begin
            if (k2_long_v) begin
                track_cmd_data_v <= 2'b10;
                track_cmd_req_v <= ~track_cmd_req_v;
                track_cmd_pending_v <= 1'b1;
            end else if (k1_long_v) begin
                track_cmd_data_v <= 2'b01;
                track_cmd_req_v <= ~track_cmd_req_v;
                track_cmd_pending_v <= 1'b1;
            end
        end
    end
end

always @(posedge sd_card_clk or posedge rst_all) begin
    if (rst_all) begin
        track_cmd_req_sd1 <= 1'b0;
        track_cmd_req_sd2 <= 1'b0;
        track_cmd_req_seen_sd <= 1'b0;
        track_cmd_data_sd1 <= 2'd0;
        track_cmd_data_sd2 <= 2'd0;
        track_cmd_ack_sd <= 1'b0;
        track_cmd_prev_sd <= 1'b0;
        track_cmd_next_sd <= 1'b0;
    end else begin
        track_cmd_req_sd1 <= track_cmd_req_v;
        track_cmd_req_sd2 <= track_cmd_req_sd1;
        track_cmd_data_sd1 <= track_cmd_data_v;
        track_cmd_data_sd2 <= track_cmd_data_sd1;
        track_cmd_prev_sd <= 1'b0;
        track_cmd_next_sd <= 1'b0;
        if (track_cmd_req_sd2 != track_cmd_req_seen_sd) begin
            track_cmd_req_seen_sd <= track_cmd_req_sd2;
            track_cmd_ack_sd <= track_cmd_req_sd2;
            if (track_cmd_data_sd2 == 2'b01)
                track_cmd_prev_sd <= 1'b1;
            else if (track_cmd_data_sd2 == 2'b10)
                track_cmd_next_sd <= 1'b1;
        end
    end
end

audio_volume_gain #(.DEFAULT_VOL(4'd0)) u_vol_gain (
    .clk(video_clk), .rst_n(~rst_all),
    .vol_up_pulse  (vol_mode_v & k2_short_v),
    .vol_down_pulse(vol_mode_v & k1_short_v),
    .in_valid(audio_valid),
    .in_left(hdmi_audio_left), .in_right(hdmi_audio_right),
    .out_left(vol_audio_l), .out_right(vol_audio_r),
    .vol_level(vol_level_a)
);

waveform_data u_waveform_data (
    .clk          (video_clk),
    .rst          (rst_all),
    .sample_valid (audio_valid),
    .frame_pulse  (e2_frame_pulse),
    .block_accept (wave_block_accept),
    .sample_left  (vol_audio_l),
    .sample_right (vol_audio_r),
    .wave_wr_en   (wave_wr_en),
    .wave_wr_addr (wave_wr_addr),
    .wave_wr_data (wave_wr_data),
    .block_done   (wave_block_done)
);

waveform_ram u_waveform_ram (
    .clk         (video_clk),
    .rst         (rst_all),
    .wr_en       (wave_wr_en),
    .wr_addr     (wave_wr_addr),
    .wr_data     (wave_wr_data),
    .block_done  (wave_block_done),
    .frame_pulse (e2_frame_pulse),
    .video_de    (de),
    .block_accept(wave_block_accept),
    .front_valid (wave_front_valid),
    .front_sel   (wave_front_sel),
    .rd_en       (wave_rd_en),
    .rd_addr     (wave_rd_addr),
    .rd_data     (wave_rd_data),
    .rd_valid    (wave_rd_valid)
);

// vol_mode 两级 FF 同步到各时钟域
reg vm_a1, vm_a2, vm_sd1, vm_sd2, vm_v1, vm_v2, vm_c1, vm_c2;
always @(posedge audio_mclk or negedge rst_n)
    if (!rst_n) begin vm_a1 <= 1'b0; vm_a2 <= 1'b0; end
    else begin vm_a1 <= vol_mode_raw; vm_a2 <= vm_a1; end
always @(posedge sd_card_clk or posedge rst_all)
    if (rst_all) begin vm_sd1 <= 1'b0; vm_sd2 <= 1'b0; end
    else begin vm_sd1 <= vol_mode_raw; vm_sd2 <= vm_sd1; end
always @(posedge video_clk or posedge rst_all)
    if (rst_all) begin vm_v1 <= 1'b0; vm_v2 <= 1'b0; end
    else begin vm_v1 <= vol_mode_raw; vm_v2 <= vm_v1; end
always @(posedge clk or negedge rst_n)
    if (!rst_n) begin vm_c1 <= 1'b0; vm_c2 <= 1'b0; end
    else begin vm_c1 <= vol_mode_raw; vm_c2 <= vm_c1; end
assign vol_mode_a  = vm_a2;
assign vol_mode_sd = vm_sd2;
assign vol_mode_v  = vm_v2;
assign vol_mode_c  = vm_c2;

// 音量档同步到数码管扫描时钟 clk(50MHz) 域（位 2 常亮显示档位）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        vol_lvl_c1  <= 4'd0; vol_lvl_c2  <= 4'd0;
    end else begin
        vol_lvl_c1  <= vol_level_a;   vol_lvl_c2  <= vol_lvl_c1;
    end
end

seg_decoder seg_decoder_vol (
    .bin_data(vol_lvl_c2),
    .seg_data(seg_data_vol)
);

audio_arc_calculate #(
    .ACR_N         (6144)
) u_audio_arc_calculate (
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_audio_valid (audio_valid),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
);

// ===================== RGB/DE 转 AXIS 视频 =====================
video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_vs          (osd_vs),
    .I_de          (osd_de),
    .I_rgb         (vout_data),
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

// 上电后自动打一拍，触发一次 EDID 读取
startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (rst_all),
    .O_pulse (edid_trig)
);

// ===================== 带音频的 HDMI 1.4b 发射 =====================
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 800        ),
    .HSA                    ( 96         ),
    .HFP                    ( 16         ),
    .HBP                    ( 48         ),
    .HACTIVE                ( 640        ),
    .VTOTAL                 ( 525        ),
    .VSA                    ( 2          ),
    .VFP                    ( 10         ),
    .VBP                    ( 33         ),
    .VACTIVE                ( 480        ),
    .VIDEO_VIC              ( 1          ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 250        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (rst_all),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (audio_valid),
    .I_audio_left_data  (vol_audio_l),
    .I_audio_right_data (vol_audio_r),
    .I_acr_valid        (acr_valid),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (rst_all),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule
