
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
wire [23:0] vout_data_mask;
   // 卡内文字叠加后
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
// V2-11：菜单渲染器请求 + 与状态栏的仲裁（菜单优先）
wire        menu_req_valid;
wire [6:0]  menu_req_ascii;
wire [7:0]  menu_req_x;
wire [6:0]  menu_req_y;
wire [1:0]  menu_req_type;
wire        menu_busy;
wire        sb_req_ready;
wire        menu_req_ready;
wire        osd_req_valid;
wire [6:0]  osd_req_ascii;
wire [7:0]  osd_req_x;
wire [6:0]  osd_req_y;
wire [1:0]  osd_req_type;
wire        menu_req_fill;
wire        osd_req_fill;
wire        osd_req_w5;
wire        osd_font_w5;
wire [7:0]  osd_f57_rd_data;
wire        osd_f57_rd_valid;
wire [7:0]  osd_f8_rd_data;
wire        osd_f8_rd_valid;
wire        osd_clr_done;

// V2-14 字幕
wire        sub_req_valid;
wire [6:0]  sub_req_ascii;
wire [7:0]  sub_req_x;
wire [6:0]  sub_req_y;
wire [1:0]  sub_req_type;
wire        sub_busy;
wire        sub_req_fill;
wire        sub_req_ready;
wire        use_w5;
// 左上角信息条（源分辨率）
wire        si_req_valid;
wire [6:0]  si_req_ascii;
wire [7:0]  si_req_x;
wire [6:0]  si_req_y;
wire [1:0]  si_req_type;
wire        si_req_ready;
wire        si_busy;

assign osd_req_valid = menu_busy ? menu_req_valid : (sub_busy ? sub_req_valid : (sb_req_valid ? sb_req_valid : si_req_valid));
assign osd_req_ascii = menu_busy ? menu_req_ascii : (sub_busy ? sub_req_ascii : (sb_req_valid ? sb_req_ascii : si_req_ascii));
assign osd_req_x     = menu_busy ? menu_req_x     : (sub_busy ? sub_req_x     : (sb_req_valid ? sb_req_x : si_req_x));
assign osd_req_y     = menu_busy ? menu_req_y     : (sub_busy ? sub_req_y     : (sb_req_valid ? sb_req_y : si_req_y));
assign osd_req_type  = menu_busy ? menu_req_type  : (sub_busy ? sub_req_type  : (sb_req_valid ? sb_req_type : si_req_type));
assign osd_req_fill  = menu_busy ? menu_req_fill  : (sub_busy ? sub_req_fill : 1'b0);
assign use_w5        = menu_busy | sub_busy | sb_req_valid | si_req_valid;   // 菜单/字幕/状态栏都用 5x7 手绘字
assign osd_req_w5    = use_w5;
assign menu_req_ready = osd_req_ready &&  menu_busy;
assign sub_req_ready  = osd_req_ready && !menu_busy &&  sub_busy;
assign sb_req_ready   = osd_req_ready && !menu_busy && !sub_busy;
assign si_req_ready   = osd_req_ready && !menu_busy && !sub_busy && !sb_req_valid;
wire [3:0]  cur_track_idx_sd;
wire [87:0] cur_track_name_sd;
wire [6:0]  cur_track_dur_mm_sd;
wire [5:0]  cur_track_dur_ss_sd;
reg  [3:0]  tki_meta, tki_sync;
reg  [87:0] tkn_meta, tkn_sync;
reg  [6:0]  tkm_meta, tkm_sync;
reg  [5:0]  tks_meta, tks_sync;
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
wire        key3_long_v;
wire        key3_trig_x   = key3_trig;
// V2-12 交互
wire        menu_panel_vis;
wire        menu_active;
wire        menu_editing;
wire [2:0]  menu_sel_row;
// V2-13 参数
wire [3:0]  m_volume;
wire [2:0]  m_bright;
wire [2:0]  m_contrast;
wire [2:0]  m_trans;
wire        m_auto;
wire [3:0]  m_period;
wire        m_info;
wire        m_tone;
wire        menu_redraw;
wire        menu_blink;
wire [2:0]  contrast_level;
wire        param_default_en;
// 任务18：按键模式（sw_key_mode：拨到ON=音量 / 未拨=切图）

wire        k1_short_v, k2_short_v;
reg         seek_tog_v, seek_fwd_v;
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
wire [239:0] spec_bands;
wire signed [23:0] vol_audio_l, vol_audio_r;
wire         spec_valid;
wire        e2_disp_changed;
wire        e2_fade_hold_done;

wire [6:0]  seg_data_img;
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
assign transition_fade_mode = ~m_trans[0];   // V2-13: 0=FADE(黑场淡入淡出) 1=WIPE(揭幕)
assign transition_busy_video = e2_transition_mode_sync && (e2_fade_state != E2_FADE_IDLE);
// V2-13: 切图只由「短按」触发（长按只切歌），方向在短按瞬间锁存
localparam [20:0] NEXT_STRETCH_CYCLES = 21'd1_250_000;   // 50ms @25MHz
reg [20:0] next_stretch;
reg        next_dir_lat;                                 // 0=下一张 1=上一张
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        next_stretch <= 21'd0;
        next_dir_lat <= 1'b0;
    end else if (k2_short_v) begin
        next_dir_lat <= 1'b1;
        next_stretch <= NEXT_STRETCH_CYCLES;
    end else if (k1_short_v) begin
        next_dir_lat <= 1'b0;
        next_stretch <= NEXT_STRETCH_CYCLES;
    end else if (next_stretch != 21'd0) begin
        next_stretch <= next_stretch - 21'd1;
    end
end

wire key_next_pulse_n = (next_stretch != 21'd0) ? 1'b0 : 1'b1;   // 低有效，宽 50ms 便于跨域
assign key1_to_sd = (transition_busy_sd_sync || menu_active) ? 1'b1 : key_next_pulse_n;

// V2-13：菜单的自动播放参数同步到 sd_card_clk 域
reg m_auto_sd1, m_auto_sd2;
always @(posedge sd_card_clk or posedge rst_all) begin
    if (rst_all) begin
        m_auto_sd1 <= 1'b0;
        m_auto_sd2 <= 1'b0;
    end else begin
        m_auto_sd1 <= m_auto;
        m_auto_sd2 <= m_auto_sd1;
    end
end

// V2-13：轮播周期 = 菜单 PERIOD（秒）× 25MHz，运行时送给 resident_switch
wire [31:0] auto_ticks_v = {24'd0, m_period} * 32'd25_000_000;

// V2-13：自动播放参数同步到视频域，直接驱动轮播（绕过 sd 模块的四级链）
reg m_auto_v1, m_auto_v2;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        m_auto_v1 <= 1'b0;
        m_auto_v2 <= 1'b0;
    end else begin
        m_auto_v1 <= m_auto;
        m_auto_v2 <= m_auto_v1;
    end
end
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
key_longshort #(
    .CLOCK_MHZ      (25),
    .LONG_CYCLES    (15_000_000),
    .REPEAT_CYCLES  (3_000_000),
    .REPEAT_ENABLE  (0)
) u_key3_longshort (
    .clk         (video_clk),
    .rst_n       (~rst_all),
    .button_in   (key3),
    .short_pulse (key3_trig),
    .long_repeat (key3_long_v),
    .long_active ()
);

wire [2:0]  brightness_level;   // V2-15: 5 档亮度（此前漏声明，被隐式当成 1 位）
assign brightness_level = m_bright;
assign contrast_level = m_contrast;

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

// ---- sd_card_clk 域状态信号同步到 video_clk 域 ----
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        bv_meta  <= 4'd0;  bv_sync  <= 4'd0;
        ar_meta  <= 1'b0;  ar_sync  <= 1'b0;
        ape_meta <= 1'b0;  ape_sync <= 1'b0;
        swd_meta <= 1'b0;  swd_sync <= 1'b0;
        tki_meta <= 4'd0;  tki_sync <= 4'd0;
        tkn_meta <= 88'd0; tkn_sync <= 88'd0;
        tkm_meta <= 7'd0;  tkm_sync <= 7'd0;
        tks_meta <= 6'd0;  tks_sync <= 6'd0;
        volv_meta<= 4'd0;  volv_sync<= 4'd0;
    end
    else begin
        bv_meta  <= bank_valid_wire;   bv_sync  <= bv_meta;
        ar_meta  <= all_resident_wire; ar_sync  <= ar_meta;
        ape_meta <= osd_auto_play_en;  ape_sync <= ape_meta;
        swd_meta <= sw_con1;           swd_sync <= swd_meta;
        tki_meta <= cur_track_idx_sd;  tki_sync <= tki_meta;
        tkn_meta <= cur_track_name_sd; tkn_sync <= tkn_meta;
        tkm_meta <= cur_track_dur_mm_sd; tkm_sync <= tkm_meta;
        tks_meta <= cur_track_dur_ss_sd; tks_sync <= tks_meta;
        volv_meta<= vol_lvl_c2;        volv_sync<= volv_meta;
    end
end

// ---- 常驻帧消隐硬切 ----
// 2026/10/24 修竞态：next_dir_lat 与 key_pulse 同一拍产生，resident_switch 若同拍采样
// dir 会读到"上一次按键"的方向（表现为按 KEY2 有时切上一张）。把 key_pulse 打一拍，
// 保证 dir 已稳定后再送进去。
reg next_key_pulse_d;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) next_key_pulse_d <= 1'b0;
    else         next_key_pulse_d <= (k1_short_v | k2_short_v) & ~menu_active & (sw_key_mode == 1'b1);
end

resident_switch #(
    .AUTO_TICKS       (25_000_000)
) resident_switch_m0(
    .clk              (video_clk),
    .rst              (rst_all),
    .frame_pulse      (e2_frame_pulse),
    .key_pulse        (next_key_pulse_d),                 // 菜单打开时不切图（已在上一拍屏蔽）
    .auto_en          (m_auto_v2),
    .auto_ticks_i     (auto_ticks_v),
    .bank_valid       (bv_sync),
    .all_resident     (ar_sync),
    .cur_disp         (e2_disp_buf_sync),
    .dir              (next_dir_lat),           // V2-13: KEY4=反向，KEY2=正向
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
    .key_next          (key1_to_sd),      // V2-13: 两键任一按下都触发切换，方向另定
    .key_auto          (1'b1),                          // V2-13: 自动播放改由菜单控制，此处不再使用
    .auto_play_ext     (m_auto_sd),
    .state_code        (),

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
    .audio_mclk        (audio_mclk),
    .video_clk         (video_clk),
    .audio_tick        (audio_valid),
    .track_cmd_prev    (track_cmd_prev_sd),
    .track_cmd_next    (track_cmd_next_sd),
    .seek_tog_v        (seek_tog_v),
    .seek_fwd_v        (seek_fwd_v),
    .wav_pcm           (wav_pcm_wire),
    .wav_pcm_valid     (),
    .wav_playing       (wav_playing_wire),
    .cur_track_index   (cur_track_idx_sd),
    .cur_track_name    (cur_track_name_sd),
    .cur_track_dur_mm  (cur_track_dur_mm_sd),
    .cur_track_dur_ss  (cur_track_dur_ss_sd)
);

seg_decoder seg_decoder_img(
    .bin_data          (img_num_display),
    .seg_data          (seg_data_img)
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
        .seg_data_5        ({1'b1,7'b111_1111}),   // 批B：状态码位废弃，常灭
    .seg_data_6        ({1'b1,7'b1111_111}),
    .seg_data_7        ({1'b1,7'b1111_111})
);

// ===================== 局部放大 2×（左卡 / 右卡）=====================
localparam [20:0] ZOOM_ROW_BASE = 21'd40320;   // 63 * 640
localparam [20:0] ZOOM_LEN      = 21'd153600;  // 240 * 640

wire        zoom_key_r = k2_long_v && (sw_key_mode == 1'b1) && !menu_panel_vis
                         && (e2_disp_buf_sync != 2'd0);   // 封面页（bank0）禁用放大

wire        seek_fwd_key = k2_short_v && (sw_key_mode == 1'b0) && !menu_active;
wire        seek_bwd_key = k1_short_v && (sw_key_mode == 1'b0) && !menu_active;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        seek_tog_v <= 1'b0;
        seek_fwd_v <= 1'b0;
    end
    else if (seek_fwd_key) begin
        seek_tog_v <= ~seek_tog_v;
        seek_fwd_v <= 1'b1;
    end
    else if (seek_bwd_key) begin
        seek_tog_v <= ~seek_tog_v;
        seek_fwd_v <= 1'b0;
    end
end

reg  [1:0] zoom_sel;
reg  [1:0] zoom_sel_v;
reg        vs_0_d;

always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        zoom_sel   <= 2'd0;
        zoom_sel_v <= 2'd0;
        vs_0_d     <= 1'b0;
    end
    else begin
        vs_0_d <= vs_0;
        if (e2_disp_buf_sync == 2'd0)
            zoom_sel <= 2'd0;                       // 封面页强制退出放大
        else if (key3_long_v && !menu_panel_vis)
            zoom_sel <= (zoom_sel == 2'd1) ? 2'd0 : 2'd1;
        else if (zoom_key_r)
            zoom_sel <= (zoom_sel == 2'd2) ? 2'd0 : 2'd2;
        if (vs_0 != vs_0_d)
            zoom_sel_v <= zoom_sel;
    end
end

wire        zoom_en_v   = (zoom_sel_v != 2'd0);
wire [9:0]  zoom_col0   = (zoom_sel_v == 2'd1) ? 10'd10 : 10'd320;

wire [23:0] zoom_data;
wire        zoom_pop;

video_zoom u_video_zoom (
    .clk       (video_clk),
    .rst       (rst_all),
    .zoom_en   (zoom_en_v),
    .col0      (zoom_col0),
    .de        (de_0),
    .vs        (vs_0),
    .fifo_data (video_read_data),
    .z_pop     (zoom_pop),
    .z_data    (zoom_data)
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
    .read_data         (zoom_en_v ? zoom_data : video_read_data[31:8]),
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

// V4：时域波形改为频谱条（24 频段 DFT）
reg [1:0] spec_emph_meta, spec_emph_lvl;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        spec_emph_meta <= 2'd0; spec_emph_lvl <= 2'd0;
    end else begin
        spec_emph_meta <= (m_tone || !wav_play_v2) ? 2'd0 : {~sw_con0, ~sw_transition};
        spec_emph_lvl  <= spec_emph_meta;
    end
end

spectrum_engine u_spectrum_engine (
    .clk          (video_clk),
    .rst          (rst_all),
    .sample_valid (audio_valid),
    .sample_r     (vol_audio_r),
    .frame_pulse  (e2_frame_pulse),
    .plain        (m_tone || !wav_play_v2),
    .bands        (spec_bands),
    .bands_valid  (spec_valid)
);

spectrum_render u_spectrum_render (
    .I_clk      (video_clk),
    .I_rst      (rst_all),
    .I_vs       (vs),
    .I_de       (de),
    .I_x        (video_x_cnt[9:0]),
    .I_y        (video_y_cnt),
    .I_rgb      (vout_data_base),
    .I_bands    (spec_bands),
    .I_emph_lvl (spec_emph_lvl),
    .O_vs       (wave_vs),
    .O_de       (wave_de),
    .O_rgb      (vout_data_wave)
);

osd_renderer u_osd_renderer (
    .clk(video_clk), .rst(rst_all), .vs(vs), .de(de),
    .req_valid(osd_req_valid),
    .req_ascii(osd_req_ascii),
    .req_x(osd_req_x),
    .req_y(osd_req_y),
    .req_type(osd_req_type),
    .req_w5(osd_req_w5),
    .req_fill(osd_req_fill),
    .req_ready(osd_req_ready),
    .font_rd_en(osd_font_rd_en),
    .font_ascii(osd_font_ascii),
    .font_row(osd_font_row),
    .font_w5(osd_font_w5),
    .font_rd_data(osd_font_rd_data),
    .font_rd_valid(osd_font_rd_valid),
    .buf_wr_en(osd_buf_wr_en),
    .buf_wr_x(osd_buf_wr_x),
    .buf_wr_y(osd_buf_wr_y),
    .buf_wr_data(osd_buf_wr_data),
    .dirty_clr(1'b0),
    .busy(osd_busy),
    .dirty_row(osd_dirty_row),
    .clr_done_o(osd_clr_done)
);

font_rom u_font_rom (
    .clk(video_clk), .rst(rst_all),
    .rd_en(osd_font_rd_en),
    .ascii(osd_font_ascii),
    .row(osd_font_row),
    .rd_data(osd_f8_rd_data),
    .rd_valid(osd_f8_rd_valid)
);

// 5x7 字库（菜单用）：与 8x8 共用同一组读地址，数据在顶层按模式选择
font5x7_rom u_font5x7_rom (
    .clk(video_clk), .rst(rst_all),
    .rd_en(osd_font_rd_en),
    .ascii(osd_font_ascii),
    .row(osd_font_row),
    .rd_data(osd_f57_rd_data),
    .rd_valid(osd_f57_rd_valid)
);

assign osd_font_rd_data  = osd_font_w5 ? osd_f57_rd_data  : osd_f8_rd_data;
assign osd_font_rd_valid = osd_font_w5 ? osd_f57_rd_valid : osd_f8_rd_valid;

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
    .I_panel_vis(menu_panel_vis),
    .I_bar_vol  (m_volume),
    .I_bar_bri  (m_bright),
    .I_bar_con  (m_contrast),
    .I_bar_sel  (menu_sel_row),          // V2-10 调试态：面板常显，V2-12 接入显隐控制
    .O_vs   (osd_vs),
    .O_de   (osd_de),
    .O_rgb  (vout_data),
    .rd_en  (osd_rd_en),
    .rd_x   (osd_rd_x),
    .rd_y   (osd_rd_y),
    .rd_data(osd_rd_data)
);

// V2-16: 删除 ui_visible_ctl（状态栏常显，不再自动淡出），省 104 LUT + 124 FF
assign ui_alpha = 3'd7;   // 7 -> 满不透明


menu_controller #(
    .CLOCK_MHZ  (25),
    .TIMEOUT_MS (15000)
) u_menu_controller (
    .clk         (video_clk),
    .rst         (rst_all),
    .minus_short (k1_short_v),
    .minus_long  (1'b0),
    .plus_short  (k2_short_v),
    .plus_long   (1'b0),
    .sel_press   (key3_trig_x),
    .vol_preset_sw(swd_sync),
    .panel_vis   (menu_panel_vis),
    .sel_row     (menu_sel_row),
    .editing     (menu_editing),
    .active      (menu_active),
    .o_volume    (m_volume),
    .o_bright    (m_bright),
    .o_contrast  (m_contrast),
    .o_trans     (m_trans),
    .o_auto      (m_auto),
    .o_period    (m_period),
    .o_info      (m_info),
    .o_tone      (m_tone),
    .redraw      (menu_redraw),
    .blink       (menu_blink)
);

subtitle_render u_subtitle_render (
    .clk        (video_clk),
    .rst        (rst_all),
    .vis        (1'b0),   // 2026/10/25 旧点阵字幕停用
    .buf_ready  (osd_clr_done),
    .vs         (vs),
    .img_idx    (e2_disp_buf_sync),
    .req_valid  (sub_req_valid),
    .req_ascii  (sub_req_ascii),
    .req_x      (sub_req_x),
    .req_y      (sub_req_y),
    .req_type   (sub_req_type),
    .req_fill   (sub_req_fill),
    .req_ready  (sub_req_ready),
    .busy       (sub_busy)
);

menu_renderer u_menu_renderer (
    .clk        (video_clk),
    .rst        (rst_all),
    .vis        (menu_panel_vis),
    .sel_row    (menu_sel_row),
    .buf_ready  (osd_clr_done),
    .redraw     (menu_redraw),
    .editing    (menu_editing),
    .blink      (menu_blink),
    .p_volume   (m_volume),
    .p_bright   (m_bright),
    .p_contrast (m_contrast),
    .p_trans    (m_trans),
    .p_auto     (m_auto),
    .p_period   (m_period),
    .p_info     (m_info),
    .p_tone     (m_tone),
    .req_valid  (menu_req_valid),
    .req_ascii  (menu_req_ascii),
    .req_x      (menu_req_x),
    .req_y      (menu_req_y),
    .req_type   (menu_req_type),
    .req_fill   (menu_req_fill),
    .req_ready  (menu_req_ready),
    .busy       (menu_busy)
);

// ---- 左上角信息条：源分辨率 ----
src_info_render u_src_info_render (
    .clk       (video_clk),
    .rst       (rst_all),
    .img_idx   (e2_disp_buf_sync),
    .src_w     (16'd0),
    .src_h     (16'd0),
    .req_valid (si_req_valid),
    .req_ascii (si_req_ascii),
    .req_x     (si_req_x),
    .req_y     (si_req_y),
    .req_type  (si_req_type),
    .req_ready (si_req_ready),
    .busy      (si_busy)
);

// ---- 曲目倒计时（视频域，供右上角状态栏显示剩余 MM:SS）----
wire        cd_active;
wire [6:0]  cd_min;
wire [5:0]  cd_sec;

track_countdown u_track_countdown (
    .clk         (video_clk),
    .rst         (rst_all),
    .vs          (vs),
    .track_idx   (tki_sync),
    .dur_min     (tkm_sync),
    .dur_sec     (tks_sync),
    .playing     (wav_play_v2),
    .adj_pulse   (seek_fwd_key | seek_bwd_key),
    .adj_fwd     (seek_fwd_key),
    .active      (cd_active),
    .rem_min     (cd_min),
    .rem_sec     (cd_sec)
);

status_bar_render u_status_bar_render (
    .clk        (video_clk),
    .rst        (rst_all),
    .track_idx  (tki_sync),
    .cd_active  (cd_active && !m_tone),
    .cd_min     (cd_min),
    .cd_sec     (cd_sec),
    .req_valid  (sb_req_valid),
    .req_ascii  (sb_req_ascii),
    .req_x      (sb_req_x),
    .req_y      (sb_req_y),
    .req_type   (sb_req_type),
    .req_ready  (sb_req_ready)
);

// V2-13: 像素效果层（亮度 / 对比度 / 转场 / 淡入淡出），不含信息栏文字
video_effect_overlay u_video_effect_overlay (
    .I_clk                 (video_clk),
    .I_rst                 (rst_all),
    .I_vs                  (wave_vs),
    .I_de                  (wave_de),
    .I_rgb                 (vout_data_wave),
    .I_brightness_level    (brightness_level),
    .I_contrast_level      (contrast_level),
    .I_fade_level          (e2_fade_level),
    .I_transition_active   (e2_transition_active),
    .I_transition_reveal_x (e2_transition_reveal_x),
    .O_rgb                 (vout_data_pre)
);

wire [20:0] rd_addr_0 = zoom_en_v ? (BANK0_ADDR[20:0] + ZOOM_ROW_BASE) : BANK0_ADDR[20:0];
wire [20:0] rd_addr_1 = zoom_en_v ? (BANK1_ADDR[20:0] + ZOOM_ROW_BASE) : BANK1_ADDR[20:0];
wire [20:0] rd_addr_2 = zoom_en_v ? (BANK2_ADDR[20:0] + ZOOM_ROW_BASE) : BANK2_ADDR[20:0];
wire [20:0] rd_addr_3 = zoom_en_v ? (BANK3_ADDR[20:0] + ZOOM_ROW_BASE) : BANK3_ADDR[20:0];
wire [20:0] rd_len    = zoom_en_v ? ZOOM_LEN : FRAME_PIXELS[20:0];
wire        fifo_re   = zoom_en_v ? zoom_pop : video_read_en;

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
    .read_addr_0       (rd_addr_0),
    .read_addr_1       (rd_addr_1),
    .read_addr_2       (rd_addr_2),
    .read_addr_3       (rd_addr_3),
    .read_addr_index   (frame_read_buf_idx),
    .read_len          (rd_len),
    .read_en           (fifo_re),
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

// ===================== 音频：数字域 DDS 测试音（48kHz 精确节拍） =====================
wire        tone_valid;
wire [23:0] tone_sample;

tone_dds u_tone_dds (
    .clk      (video_clk),
    .rst      (rst_all),
    .o_valid  (tone_valid),
    .o_sample (tone_sample)
);

assign audio_valid      = tone_valid;
assign audio_left_data  = tone_sample;
assign audio_right_data = tone_sample;

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
assign hdmi_audio_left  = (wav_play_v2 && !m_tone) ? wav_pcm24 : audio_left_data;
assign hdmi_audio_right = (wav_play_v2 && !m_tone) ? wav_pcm24 : audio_right_data;

// ===================== 任务 18：数字音量调节（拨码切模式，短按一下一档）=====================
wire [3:0]  vol_level_a;

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
        if (!track_cmd_pending_v && !menu_active) begin
            if (k2_long_v && (sw_key_mode == 1'b0)) begin
                track_cmd_data_v <= 2'b10;
                track_cmd_req_v <= ~track_cmd_req_v;
                track_cmd_pending_v <= 1'b1;
            end else if (k1_long_v && (sw_key_mode == 1'b0)) begin
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

audio_volume_gain #(.DEFAULT_VOL(4'd0), .EXTERNAL_LEVEL(1)) u_vol_gain (
    .clk(video_clk), .rst_n(~rst_all),
    .vol_up_pulse  (1'b0),
    .vol_down_pulse(1'b0),
    .external_vol_level(m_volume),
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
// ===================== 卡内文字 mask 叠加（最后一级）=====================
wire [9:0] mask_slide_off;
wire       mask_trans_busy = e2_transition_active | transition_busy_video | e2_transition_pending;
wire       mask_hide       = menu_panel_vis | zoom_en_v;

mask_slide u_mask_slide (
    .clk          (video_clk),
    .rst          (rst_all),
    .page_changed (e2_disp_changed),
    .trans_active (mask_trans_busy),
    .frame_tick   (e2_frame_pulse),
    .slide        (mask_slide_off)
);

mask_overlay u_mask_overlay (
    .clk       (video_clk),
    .rst       (rst_all),
    .de        (osd_de),
    .x         (video_x_cnt[9:0]),
    .y         (video_y_cnt),
    .rgb_in    (vout_data),
    .panel_vis (mask_hide),
    .mask_en   (1'b1),
    .page      (e2_disp_buf_sync),
    .slide_l   (mask_slide_off),
    .slide_r   (mask_slide_off),
    .rgb_out   (vout_data_mask)
);

video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_vs          (osd_vs),
    .I_de          (osd_de),
        .I_rgb         (vout_data_mask),
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
