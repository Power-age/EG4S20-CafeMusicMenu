
module sd_card_bmp #(
    parameter integer CLK_FREQ_HZ       = 100_000_000,
    parameter [31:0]  SCAN_START_SECTOR = 32'd0,
    parameter [31:0]  SCAN_MAX_SECTOR   = 32'd131071,
    parameter [2:0]   SCAN_TARGET_COUNT = 3'd4
)(
    input                       clk,
    input                       rst,
    input                       key_next,
    input                       key_auto,
    input                       auto_play_ext,   // V2-13: 自动播放由设置面板控制
    output [3:0]                state_code,
    output [3:0]                bank_valid_out,
    output                      all_resident_out,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output reg                  display_valid,
    output                      osd_auto_play_en,
    output reg [15:0]           display_active_width,
    output reg [15:0]           display_active_height,
    output reg [15:0]           display_active_offset_x,
    output reg [15:0]           display_active_offset_y,

    input                       write_finish_toggle,
    output [1:0]                write_buf_idx,
    output reg [1:0]            disp_buf_idx,

    output                      write_req,
    input                       write_req_ack,
    output [20:0]               write_len,
    output [15:0]               write_active_width,
    output [15:0]               write_active_height,
    output [15:0]               write_active_offset_x,
    output [15:0]               write_active_offset_y,
    output                      write_en,
    output [31:0]               write_data,
    output                      SD_nCS,
    output                      SD_DCLK,
    output                      SD_MOSI,
    input                       SD_MISO,
    output [1:0]                img_idx_out,

    // WAV 播放器：读侧音频时钟/节拍（top 提供），PCM 输出（top mux）
    input                       audio_mclk,
    input                       video_clk,   // 读侧与 HDMI 采样统一到 video 域
    input                       audio_tick,
    input                       track_cmd_prev,
    input                       track_cmd_next,
    input                       seek_tog_v,
    input                       seek_fwd_v,
    output [15:0]               wav_pcm,
    output                      wav_pcm_valid,
    output                      wav_playing,
    output [3:0]                cur_track_index,
    output [87:0]               cur_track_name,
    output [6:0]                cur_track_dur_mm,   // 当前曲目总长（分）
    output [5:0]                cur_track_dur_ss    // 当前曲目总长（秒）
);

wire key_next_press;
wire key_auto_press;

wire [31:0] wav_bytes_consumed;
wire [31:0] wav_start_sector;

reg  seek_tog_meta, seek_tog_sync, seek_tog_seen;
reg  seek_dir_meta, seek_dir_sync;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        seek_tog_meta <= 1'b0;
        seek_tog_sync <= 1'b0;
        seek_tog_seen <= 1'b0;
        seek_dir_meta <= 1'b0;
        seek_dir_sync <= 1'b0;
    end
    else begin
        seek_tog_meta <= seek_tog_v;
        seek_tog_sync <= seek_tog_meta;
        seek_tog_seen <= seek_tog_sync;
        seek_dir_meta <= seek_fwd_v;
        seek_dir_sync <= seek_dir_meta;
    end
end

wire seek_req_c = seek_tog_sync ^ seek_tog_seen;
wire seek_fwd_c = seek_dir_sync;

wire             sd_sec_read;
wire [31:0]      sd_sec_read_addr;
wire [7:0]       sd_sec_read_data;
wire             sd_sec_read_data_valid;
wire             sd_sec_read_end;
wire             bmp_data_wr_en;
wire [23:0]      bmp_data;
wire             sd_init_done;
wire             bmp_ready;
wire             scan_done;
wire             scan_found_valid;
wire [31:0]      scan_found_sector;
wire [2:0]       scan_found_total;
wire [15:0]      bmp_active_width;
wire [15:0]      bmp_active_height;
wire [15:0]      bmp_active_offset_x;
wire [15:0]      bmp_active_offset_y;
wire [20:0]      bmp_active_pixel_count;
wire        bmp_sec_read;
wire [31:0] bmp_sec_addr;
wire [7:0]  bmp_sec_data;
wire        bmp_sec_valid;
wire        bmp_sec_end;
wire        bmp_sec_error;
wire        sd_sec_read_request;
wire        sd_sec_read_error;
wire        bmp_load_error;
wire        bmp_load_complete;
wire        scn_sec_req;
wire [31:0] scn_sec_lba;
wire        scn_sec_busy;
wire        scn_sec_valid;
wire [7:0]  scn_sec_byte;
wire [8:0]  scn_sec_byte_index;
wire        scn_sec_done;
wire [7:0]  scn_sec_error;
wire        scn_scan_done;
wire [7:0]  scn_fs_error;
wire [7:0]  scn_spc;
wire [31:0] scn_data_start;
wire [31:0] scn_fat_start;
wire [31:0] scn_max_cluster;

wire        chain_m_req;
wire [31:0] chain_m_addr;
wire [7:0]  chain_to_bmp_data;
wire        chain_to_bmp_valid;
wire        chain_to_bmp_end;
wire        chain_to_bmp_error;

wire [3:0]  scn_resource_valid;
wire [31:0] scn_res0_cluster;
wire [31:0] scn_res1_cluster;
wire [31:0] scn_res2_cluster;
wire [31:0] scn_res3_cluster;
wire [31:0] scn_res0_size;
wire [31:0] scn_res1_size;
wire [31:0] scn_res2_size;
wire [31:0] scn_res3_size;
wire        scn_music_valid;
wire [31:0] scn_music_cluster;
wire [31:0] scn_music_size;
wire        scn_track_push;
wire [3:0]  scn_track_index;
wire [87:0] scn_track_name;
wire [31:0] scn_track_cluster;
wire [31:0] scn_track_size;
wire [15:0] track_valid_mask;
wire [4:0]  track_count;
wire        track_lookup_req;
wire [3:0]  track_lookup_index;
wire        track_lookup_valid;
wire [87:0] track_lookup_name;
wire [31:0] track_lookup_cluster;
wire [31:0] track_lookup_size;
wire        track_player_start;
wire        track_player_stop;
wire [31:0] track_player_size;
wire        track_chain_load;
wire [31:0] track_chain_cluster;
wire        playlist_active;
wire [3:0]  current_track_index;
wire [87:0] current_track_name;

// WAV 簇链与三源仲裁
wire        wav_chain_m_req;
wire [31:0] wav_chain_m_addr;
wire [7:0]  wav_chain_data;
wire        wav_chain_valid;
wire        wav_chain_end;
wire        wav_chain_error;
wire [1:0]  sec_grant;
wire        sec_grant_valid;
wire        wav_load_start;
reg         all_res_d;

// wav player 写侧(chain bmp)与控制
wire        wav_pcreq;
wire [31:0] wav_pck;
wire        wav_play_busy;
wire        wav_source_done;
wire        wav_play_finish;
wire        wav_play_error;
reg         scan_phase;
reg         scan_done_lvl;
reg         scn_read_lvl;
reg [8:0]   scn_byte_cnt;
reg         scn_busy_reg;
reg [25:0]  sd_read_timeout_cnt;
reg         sd_read_timeout_expired;
reg         sd_read_timeout_pulse;
reg         sd_read_abort_pulse;

reg              scan_start_pulse;
reg              load_start_pulse;
reg [31:0]       load_cluster;
reg              scan_kicked;
reg              first_image_committed;
reg              auto_play_en;
reg [31:0]       auto_cnt;
reg [2:0]        img_found_count;
reg [1:0]        img_idx;              // 当前真正显示中的图片编号
reg [1:0]        load_idx;             // 当前正在写入的图片编号
reg [1:0]        pending_buf_idx;      // 当前正在写入的目标缓冲区
reg [15:0]       pending_active_width;
reg [15:0]       pending_active_height;
reg [15:0]       pending_active_offset_x;
reg [15:0]       pending_active_offset_y;
reg [20:0]       pending_active_pixel_count;
reg [31:0]       img_cluster0;
reg [31:0]       img_cluster1;
reg [31:0]       img_cluster2;
reg [31:0]       img_cluster3;
reg [31:0]       img_file_size0;
reg [31:0]       img_file_size1;
reg [31:0]       img_file_size2;
reg [31:0]       img_file_size3;
reg              next_req_pending;
reg              load_busy;
reg              write_finish_seen;
reg              load_retry_used;
reg [3:0]        bad_image_mask;
reg [3:0]        bank_valid;
reg              all_resident;
reg [2:0]        next_load_idx;

// ---- 上电清 4 bank 为黑（背景）控制 ----
localparam [3:0] C_IDLE = 4'd0, C_REQ = 4'd1, C_RV = 4'd2,
                 C_FEED = 4'd3, C_NEXT = 4'd4, C_FIN = 4'd5;
reg [3:0]  clear_cst;
reg [1:0]  clear_bank;
reg        clear_req_r;
reg        clear_feed_r;
reg        clear_done_r;
reg [1:0]  load_write_buf_idx;
wire       clear_active;
wire       bmp_write_req;

// ---- 临时：死机原因诊断（定位后移除）----

// bmp_ready 先表示“源文件读取/送 FIFO 完成”；真正切显示要等 write_finish_toggle 同步后
reg              source_done_seen;

// 同步 mem_clk 域的 write_finish_toggle
reg [2:0]        wrfin_tgl_sync;
wire             write_finish_pulse;

reg              wr_ack_meta;
reg              wr_ack_sync;

wire auto_tick;

assign write_en   = clear_active ? clear_feed_r   : bmp_data_wr_en;
assign write_data = clear_active ? 32'd0
                                : {bmp_data[23:16], bmp_data[15:8], bmp_data[7:0], 8'b0};
assign write_len  = clear_active ? 21'd307200     : bmp_active_pixel_count;
assign write_active_width    = clear_active ? 16'd640 : bmp_active_width;
assign write_active_height   = clear_active ? 16'd480 : bmp_active_height;
assign write_active_offset_x = clear_active ? 16'd0   : bmp_active_offset_x;
assign write_active_offset_y = clear_active ? 16'd0   : bmp_active_offset_y;
assign write_buf_idx  = clear_active ? clear_bank : load_write_buf_idx;
assign write_req     = clear_active ? clear_req_r : bmp_write_req;
assign clear_active  = (clear_cst != C_IDLE) && (clear_cst != C_FIN);
assign osd_auto_play_en = auto_play_en;
assign auto_tick  = (auto_cnt == (CLK_FREQ_HZ - 1));
assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];
assign img_idx_out = img_idx;
assign cur_track_index = current_track_index;
assign cur_track_name = current_track_name;

// ---- 曲目总长换算（本域完成，避免视频域放 32 位减法器）----
// 96 000 字节/秒（16bit 单声道 48kHz）。重复减法，一首 5 分钟的曲子约 300 次迭代。
localparam [31:0] BYTES_PER_SEC_T = 32'd96000;
reg [31:0] dur_rest;
reg [6:0]  dur_mm_r;
reg [5:0]  dur_ss_r;
reg        dur_busy;
reg [31:0] dur_size_q;

assign cur_track_dur_mm = dur_mm_r;
assign cur_track_dur_ss = dur_ss_r;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        dur_rest   <= 32'd0;
        dur_mm_r   <= 7'd0;
        dur_ss_r   <= 6'd0;
        dur_busy   <= 1'b0;
        dur_size_q <= 32'd0;
    end else if (!dur_busy) begin
        if (track_player_size != dur_size_q) begin
            dur_size_q <= track_player_size;
            dur_rest   <= track_player_size;
            dur_mm_r   <= 7'd0;
            dur_ss_r   <= 6'd0;
            dur_busy   <= 1'b1;
        end
    end else begin
        if (dur_rest >= BYTES_PER_SEC_T) begin
            dur_rest <= dur_rest - BYTES_PER_SEC_T;
            if (dur_ss_r >= 6'd59) begin
                dur_ss_r <= 6'd0;
                if (dur_mm_r >= 7'd99) begin
                    dur_mm_r <= 7'd99;
                    dur_busy <= 1'b0;
                end else dur_mm_r <= dur_mm_r + 7'd1;
            end else dur_ss_r <= dur_ss_r + 6'd1;
        end else begin
            dur_busy <= 1'b0;
        end
    end
end
assign bank_valid_out = bank_valid;
assign all_resident_out = all_resident;
// 仅在仲裁锁定(grant_valid=1)时按 grant 接通，空闲窗口一律 request=0
assign sd_sec_read_request = sec_grant_valid ?
    ((sec_grant==2'd0) ? scn_read_lvl :
     (sec_grant==2'd2) ? wav_chain_m_req : chain_m_req) : 1'b0;
assign sd_sec_read      = sd_sec_read_request && !sd_read_timeout_expired;
assign sd_sec_read_addr =
    (sec_grant==2'd0) ? scn_sec_lba :
    (sec_grant==2'd2) ? wav_chain_m_addr : chain_m_addr;
assign scn_sec_busy       = scn_busy_reg;
assign scn_sec_valid      = scan_phase ? sd_sec_read_data_valid : 1'b0;
assign scn_sec_byte       = sd_sec_read_data;
assign scn_sec_byte_index = scn_byte_cnt;
assign scn_sec_done       = scan_phase ? (sd_sec_read_end || sd_read_timeout_pulse) : 1'b0;
assign scn_sec_error      = (scan_phase && sd_read_timeout_pulse) ? 8'h10 : 8'd0;
assign sd_sec_read_error  = sd_read_timeout_pulse;
assign bmp_sec_data  = chain_to_bmp_data;
assign bmp_sec_valid = chain_to_bmp_valid;
assign bmp_sec_end   = chain_to_bmp_end;
assign bmp_sec_error = chain_to_bmp_error || (!scan_phase && sd_read_timeout_pulse);
assign scan_done = scan_done_lvl;

// 四图常驻完成（上升沿）且扫到 MUSIC.WAV -> 加载 WAV 簇链起点
always @(posedge clk or posedge rst) begin
    if (rst) all_res_d <= 1'b0;
    else     all_res_d <= all_resident;
end
assign wav_load_start = track_chain_load;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        sd_read_timeout_cnt     <= 26'd0;
        sd_read_timeout_expired <= 1'b0;
        sd_read_timeout_pulse   <= 1'b0;
        sd_read_abort_pulse     <= 1'b0;
    end else begin
        sd_read_timeout_pulse <= 1'b0;
        sd_read_abort_pulse   <= 1'b0;
        if (!sd_sec_read_request || sd_sec_read_end || sd_sec_read_error) begin
            sd_read_timeout_cnt     <= 26'd0;
            sd_read_timeout_expired <= 1'b0;
        end else if (!sd_read_timeout_expired) begin
            if (sd_read_timeout_cnt == 26'd49_999_999) begin
                sd_read_timeout_cnt     <= sd_read_timeout_cnt;
                sd_read_timeout_expired <= 1'b1;
                sd_read_timeout_pulse   <= 1'b1;
                sd_read_abort_pulse     <= 1'b1;
            end else begin
                sd_read_timeout_cnt <= sd_read_timeout_cnt + 26'd1;
            end
        end
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        scan_phase    <= 1'b0;
        scan_done_lvl <= 1'b0;
        scn_read_lvl  <= 1'b0;
        scn_byte_cnt  <= 9'd0;
        scn_busy_reg  <= 1'b0;
    end else begin
        if (!scan_kicked && sd_init_done) begin
            scan_phase    <= 1'b1;
            scan_done_lvl <= 1'b0;
        end else if (scan_start_pulse) begin
            scan_phase    <= 1'b1;
            scan_done_lvl <= 1'b0;
        end
        if (scn_scan_done) begin
            scan_phase    <= 1'b0;
            scan_done_lvl <= 1'b1;
        end
        if (scan_phase) begin
            if (scn_sec_req && !scn_busy_reg) begin
                scn_read_lvl <= 1'b1;
                scn_busy_reg <= 1'b1;
                scn_byte_cnt <= 9'd0;
            end
            else if (sd_sec_read_end || sd_read_timeout_pulse) begin
                scn_read_lvl <= 1'b0;
                scn_busy_reg <= 1'b0;
                scn_byte_cnt <= 9'd0;
            end
            else if (sd_sec_read_data_valid)
                scn_byte_cnt <= scn_byte_cnt + 9'd1;
        end
    end
end

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_next (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_next),
    .press_pulse(key_next_press)
);

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_auto (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_auto),
    .press_pulse(key_auto_press)
);

function [1:0] next_index_limited;
    input [1:0] cur;
    input [2:0] count;
    begin
        case (count)
            3'd0: next_index_limited = 2'd0;
            3'd1: next_index_limited = 2'd0;
            3'd2: next_index_limited = (cur == 2'd1) ? 2'd0 : (cur + 2'd1);
            3'd3: next_index_limited = (cur == 2'd2) ? 2'd0 : (cur + 2'd1);
            default: next_index_limited = (cur == 2'd3) ? 2'd0 : (cur + 2'd1);
        endcase
    end
endfunction
function [1:0] prev_index_limited;
    input [1:0] cur;
    input [2:0] count;
    begin
        case (count)
            3'd0: prev_index_limited = 2'd0;
            3'd1: prev_index_limited = 2'd0;
            3'd2: prev_index_limited = (cur == 2'd0) ? 2'd1 : (cur - 2'd1);
            3'd3: prev_index_limited = (cur == 2'd0) ? 2'd2 : (cur - 2'd1);
            default: prev_index_limited = (cur == 2'd0) ? 2'd3 : (cur - 2'd1);
        endcase
    end
endfunction

function [1:0] next_good_index;
    input [1:0] cur;
    input [2:0] count;
    input [3:0] bad_mask;
    begin
        next_good_index = cur;
        case (count)
            3'd2: begin
                if (cur == 2'd0) begin
                    if (!bad_mask[1]) next_good_index = 2'd1;
                end else if (!bad_mask[0]) begin
                    next_good_index = 2'd0;
                end
            end
            3'd3: begin
                case (cur)
                    2'd0: begin
                        if (!bad_mask[1]) next_good_index = 2'd1;
                        else if (!bad_mask[2]) next_good_index = 2'd2;
                    end
                    2'd1: begin
                        if (!bad_mask[2]) next_good_index = 2'd2;
                        else if (!bad_mask[0]) next_good_index = 2'd0;
                    end
                    default: begin
                        if (!bad_mask[0]) next_good_index = 2'd0;
                        else if (!bad_mask[1]) next_good_index = 2'd1;
                    end
                endcase
            end
            3'd4: begin
                case (cur)
                    2'd0: begin
                        if (!bad_mask[1]) next_good_index = 2'd1;
                        else if (!bad_mask[2]) next_good_index = 2'd2;
                        else if (!bad_mask[3]) next_good_index = 2'd3;
                    end
                    2'd1: begin
                        if (!bad_mask[2]) next_good_index = 2'd2;
                        else if (!bad_mask[3]) next_good_index = 2'd3;
                        else if (!bad_mask[0]) next_good_index = 2'd0;
                    end
                    2'd2: begin
                        if (!bad_mask[3]) next_good_index = 2'd3;
                        else if (!bad_mask[0]) next_good_index = 2'd0;
                        else if (!bad_mask[1]) next_good_index = 2'd1;
                    end
                    default: begin
                        if (!bad_mask[0]) next_good_index = 2'd0;
                        else if (!bad_mask[1]) next_good_index = 2'd1;
                        else if (!bad_mask[2]) next_good_index = 2'd2;
                    end
                endcase
            end
            default: next_good_index = 2'd0;
        endcase
    end
endfunction

function [1:0] prev_good_index;
    input [1:0] cur;
    input [2:0] count;
    input [3:0] bad_mask;
    begin
        prev_good_index = cur;
        case (count)
            3'd2: begin
                if (cur == 2'd0) begin
                    if (!bad_mask[1]) prev_good_index = 2'd1;
                end else if (!bad_mask[0]) begin
                    prev_good_index = 2'd0;
                end
            end
            3'd3: begin
                case (cur)
                    2'd0: begin
                        if (!bad_mask[2]) prev_good_index = 2'd2;
                        else if (!bad_mask[1]) prev_good_index = 2'd1;
                    end
                    2'd1: begin
                        if (!bad_mask[0]) prev_good_index = 2'd0;
                        else if (!bad_mask[2]) prev_good_index = 2'd2;
                    end
                    default: begin
                        if (!bad_mask[1]) prev_good_index = 2'd1;
                        else if (!bad_mask[0]) prev_good_index = 2'd0;
                    end
                endcase
            end
            3'd4: begin
                case (cur)
                    2'd0: begin
                        if (!bad_mask[3]) prev_good_index = 2'd3;
                        else if (!bad_mask[2]) prev_good_index = 2'd2;
                        else if (!bad_mask[1]) prev_good_index = 2'd1;
                    end
                    2'd1: begin
                        if (!bad_mask[0]) prev_good_index = 2'd0;
                        else if (!bad_mask[3]) prev_good_index = 2'd3;
                        else if (!bad_mask[2]) prev_good_index = 2'd2;
                    end
                    2'd2: begin
                        if (!bad_mask[1]) prev_good_index = 2'd1;
                        else if (!bad_mask[0]) prev_good_index = 2'd0;
                        else if (!bad_mask[3]) prev_good_index = 2'd3;
                    end
                    default: begin
                        if (!bad_mask[2]) prev_good_index = 2'd2;
                        else if (!bad_mask[1]) prev_good_index = 2'd1;
                        else if (!bad_mask[0]) prev_good_index = 2'd0;
                    end
                endcase
            end
            default: prev_good_index = 2'd0;
        endcase
    end
endfunction

function good_image_exists;
    input [2:0] count;
    input [3:0] bad_mask;
    integer idx;
    begin
        good_image_exists = 1'b0;
        for (idx = 0; idx < 4; idx = idx + 1)
            if ((idx < count) && !bad_mask[idx])
                good_image_exists = 1'b1;
    end
endfunction

function [31:0] file_size_lut;
    input [1:0] idx;
    begin
        case (idx)
            2'd0: file_size_lut = img_file_size0;
            2'd1: file_size_lut = img_file_size1;
            2'd2: file_size_lut = img_file_size2;
            2'd3: file_size_lut = img_file_size3;
            default: file_size_lut = 32'd0;
        endcase
    end
endfunction

function [31:0] cluster_lut;
    input [1:0] idx;
    begin
        case (idx)
            2'd0: cluster_lut = img_cluster0;
            2'd1: cluster_lut = img_cluster1;
            2'd2: cluster_lut = img_cluster2;
            2'd3: cluster_lut = img_cluster3;
            default: cluster_lut = img_cluster0;
        endcase
    end
endfunction

function [1:0] next_buf_lut;
    input [1:0] cur_disp_buf;
    input       valid_now;
    begin
        if (!valid_now)
            next_buf_lut = 2'd0;                 // 首图固定写 buffer0
        else if (cur_disp_buf == 2'd0)
            next_buf_lut = 2'd1;
        else
            next_buf_lut = 2'd0;
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        wr_ack_meta <= 1'b0;
        wr_ack_sync <= 1'b0;
    end else begin
        wr_ack_meta <= write_req_ack;
        wr_ack_sync <= wr_ack_meta;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        wrfin_tgl_sync        <= 3'b000;
        scan_start_pulse      <= 1'b0;
        load_start_pulse      <= 1'b0;
        load_cluster           <= 32'd0;
        scan_kicked           <= 1'b0;
        first_image_committed <= 1'b0;
        auto_play_en          <= 1'b0;
        auto_cnt              <= 32'd0;
        img_found_count       <= 3'd0;
        img_idx               <= 2'd0;
        load_idx              <= 2'd0;
        pending_buf_idx       <= 2'd0;
        pending_active_width  <= 16'd640;
        pending_active_height <= 16'd480;
        pending_active_offset_x <= 16'd0;
        pending_active_offset_y <= 16'd0;
        pending_active_pixel_count <= 21'd307200;
        load_write_buf_idx    <= 2'd0;
        disp_buf_idx          <= 2'd0;
        display_active_width  <= 16'd640;
        display_active_height <= 16'd480;
        display_active_offset_x <= 16'd0;
        display_active_offset_y <= 16'd0;
        img_cluster0          <= 32'd0;
        img_cluster1          <= 32'd0;
        img_cluster2          <= 32'd0;
        img_cluster3          <= 32'd0;
        next_req_pending      <= 1'b0;
        load_busy             <= 1'b0;
        source_done_seen      <= 1'b0;
        write_finish_seen     <= 1'b0;
        load_retry_used       <= 1'b0;
        bad_image_mask        <= 4'd0;
        bank_valid            <= 4'd0;
        all_resident          <= 1'b0;
        next_load_idx         <= 3'd0;
        display_valid         <= 1'b0;
    end else begin
        wrfin_tgl_sync   <= {wrfin_tgl_sync[1:0], write_finish_toggle};
        scan_start_pulse <= 1'b0;
        load_start_pulse <= 1'b0;

        if (!sd_init_done) begin
            scan_kicked           <= 1'b0;
            img_found_count       <= 3'd0;
            load_busy             <= 1'b0;
            source_done_seen      <= 1'b0;
            write_finish_seen     <= 1'b0;
            load_retry_used       <= 1'b0;
            bad_image_mask        <= 4'd0;
            bank_valid            <= 4'd0;
            all_resident          <= 1'b0;
            next_load_idx         <= 3'd0;
            next_req_pending      <= 1'b0;
            auto_cnt              <= 32'd0;
        end else begin
            if (bmp_load_error && load_busy) begin
                load_busy        <= 1'b0;
                source_done_seen <= 1'b0;
                write_finish_seen <= 1'b0;
                if (!load_retry_used) begin
                    load_retry_used <= 1'b1;
                    if (good_image_exists(img_found_count, bad_image_mask)) begin
                        load_start_pulse <= 1'b1;
                        load_busy        <= 1'b1;
                    end
                end else begin
                    bad_image_mask[load_idx] <= 1'b1;
                    load_retry_used  <= 1'b0;
                    load_busy        <= 1'b0;
                    source_done_seen <= 1'b0;
                    write_finish_seen <= 1'b0;
                end
            end

            // 扫描阶段缓存前 4 张图的起始 sector
            if (scn_scan_done) begin
                img_cluster0 <= scn_resource_valid[0] ? scn_res0_cluster : 32'd0;
                img_cluster1 <= scn_resource_valid[1] ? scn_res1_cluster : 32'd0;
                img_cluster2 <= scn_resource_valid[2] ? scn_res2_cluster : 32'd0;
                img_cluster3 <= scn_resource_valid[3] ? scn_res3_cluster : 32'd0;
                img_file_size0 <= scn_resource_valid[0] ? scn_res0_size : 32'd0;
                img_file_size1 <= scn_resource_valid[1] ? scn_res1_size : 32'd0;
                img_file_size2 <= scn_resource_valid[2] ? scn_res2_size : 32'd0;
                img_file_size3 <= scn_resource_valid[3] ? scn_res3_size : 32'd0;
                img_found_count <= {2'd0,scn_resource_valid[0]} + {2'd0,scn_resource_valid[1]}
                                 + {2'd0,scn_resource_valid[2]} + {2'd0,scn_resource_valid[3]};
            end

            // 记住 bmp_read 已经把源图送完 FIFO，但还不能切显示，得等整帧写完
            if (load_busy && write_req) begin
                pending_active_width <= bmp_active_width;
                pending_active_height <= bmp_active_height;
                pending_active_offset_x <= bmp_active_offset_x;
                pending_active_offset_y <= bmp_active_offset_y;
                pending_active_pixel_count <= bmp_active_pixel_count;
            end

            if (load_busy && write_finish_pulse && !bmp_load_error)
                write_finish_seen <= 1'b1;

            if (load_busy && bmp_load_complete && !bmp_load_error)
                source_done_seen <= 1'b1;

            // 只有真正收到 write_finish_toggle 脉冲，才提交新图并切换显示缓冲区
            if (load_busy && !bmp_load_error && (source_done_seen || bmp_load_complete) && (write_finish_seen || write_finish_pulse)) begin
                bank_valid[load_idx]  <= 1'b1;
                load_busy             <= 1'b0;
                source_done_seen      <= 1'b0;
                write_finish_seen     <= 1'b0;
                load_retry_used       <= 1'b0;
                if (!first_image_committed) begin
                    disp_buf_idx          <= load_idx;
                    img_idx               <= load_idx;
                    display_active_width  <= pending_active_width;
                    display_active_height <= pending_active_height;
                    display_active_offset_x <= pending_active_offset_x;
                    display_active_offset_y <= pending_active_offset_y;
                    display_valid         <= 1'b1;
                    first_image_committed <= 1'b1;
                end
            end

            // 上电后自动发起一次“扫描前 4 张 BMP”
            if (!scan_kicked && sd_init_done) begin
                scan_start_pulse      <= 1'b1;
                scan_kicked           <= 1'b1;
                first_image_committed <= 1'b0;
                bank_valid            <= 4'd0;
                all_resident          <= 1'b0;
                next_load_idx         <= 3'd0;
                auto_play_en          <= 1'b0;
                img_idx               <= 2'd0;
                load_idx              <= 2'd0;
                pending_buf_idx       <= 2'd0;
                pending_active_width  <= 16'd640;
                pending_active_height <= 16'd480;
                pending_active_offset_x <= 16'd0;
                pending_active_offset_y <= 16'd0;
                pending_active_pixel_count <= 21'd307200;
                load_write_buf_idx    <= 2'd0;
                disp_buf_idx          <= 2'd0;
                display_active_width  <= 16'd640;
                display_active_height <= 16'd480;
                display_active_offset_x <= 16'd0;
                display_active_offset_y <= 16'd0;
                display_valid         <= 1'b0;
                auto_cnt              <= 32'd0;
                img_found_count       <= 3'd0;
                next_req_pending      <= 1'b0;
                load_busy             <= 1'b0;
                source_done_seen      <= 1'b0;
                write_finish_seen     <= 1'b0;
            end else begin
                // 忙的时候也只记 1 次“下一张”请求，不会累积成连跳两张
                if (key_next_press && scan_done && (img_found_count > 3'd0))
                    next_req_pending <= 1'b1;

                // 自动播放开/关（顺序装载阶段不允许开启）
                // V2-13: 自动播放直接跟随设置面板参数（需 ≥2 张图）
                if (scan_done && (img_found_count > 3'd1))
                    auto_play_en <= auto_play_ext;
                else
                    auto_play_en <= 1'b0;

                // 自动播放 1s 计数：只有当前没有写图任务时才计时
                if (scan_done && auto_play_en && display_valid && !load_busy && first_image_committed && (img_found_count > 3'd1)) begin
                    if (auto_tick)
                        auto_cnt <= 32'd0;
                    else
                        auto_cnt <= auto_cnt + 32'd1;
                end else begin
                    auto_cnt <= 32'd0;
                end

                // 顺序装载：按 next_load_idx 逐张写入固定 bank（图号即 bank）
                if (scan_done && clear_done_r && !all_resident && bmp_ready && !load_busy
                        && (next_load_idx < img_found_count)) begin
                    load_idx          <= next_load_idx[1:0];
                    load_cluster      <= cluster_lut(next_load_idx[1:0]);
                    pending_buf_idx   <= next_load_idx[1:0];
                    load_write_buf_idx <= next_load_idx[1:0];
                    load_start_pulse  <= 1'b1;
                    load_busy         <= 1'b1;
                    source_done_seen  <= 1'b0;
                    write_finish_seen <= 1'b0;
                    load_retry_used   <= 1'b0;
                    next_req_pending  <= 1'b0;
                    auto_cnt          <= 32'd0;
                    next_load_idx     <= next_load_idx + 3'd1;
                end
                else if (scan_done && clear_done_r && !all_resident && !load_busy
                        && (next_load_idx >= img_found_count)) begin
                    all_resident <= 1'b1;
                end
            end
        end
    end
end

// ---- 上电清 4 bank 为黑（背景）----
always @(posedge clk or posedge rst) begin
    if (rst || !sd_init_done) begin
        clear_cst    <= C_IDLE;
        clear_bank   <= 2'd0;
        clear_req_r  <= 1'b0;
        clear_feed_r <= 1'b0;
        clear_done_r <= 1'b0;
    end else begin
        clear_req_r  <= 1'b0;
        clear_feed_r <= 1'b0;
        case (clear_cst)
            C_IDLE: if (sd_init_done)
                        clear_cst <= C_REQ;
            C_REQ: begin
                clear_req_r <= 1'b1;
                if (wr_ack_sync)
                    clear_cst <= C_RV;
            end
            C_RV:  clear_cst <= C_FEED;
            C_FEED: begin
                clear_feed_r <= 1'b1;
                if (write_finish_pulse)
                    clear_cst <= C_NEXT;
            end
            C_NEXT: begin
                if (clear_bank == 2'd3) begin
                    clear_done_r <= 1'b1;
                    clear_cst    <= C_FIN;
                end else begin
                    clear_bank <= clear_bank + 2'd1;
                    clear_cst  <= C_REQ;
                end
            end
            C_FIN: clear_cst <= C_FIN;
            default: clear_cst <= C_IDLE;
        endcase
    end
end


fat32_volume_scanner u_scanner(
    .clk                (clk),
    .rst_n              (~rst),
    .scan_start         (scan_start_pulse),
    .scan_busy          (),
    .scan_done          (scn_scan_done),
    .fs_error           (scn_fs_error),
    .partition_lba      (),
    .sectors_per_cluster(scn_spc),
    .fat_start_lba      (scn_fat_start),
    .data_start_lba     (scn_data_start),
    .max_cluster        (scn_max_cluster),
    .resource_valid     (scn_resource_valid),
    .resource0_cluster  (scn_res0_cluster),
    .resource1_cluster  (scn_res1_cluster),
    .resource2_cluster  (scn_res2_cluster),
    .resource3_cluster  (scn_res3_cluster),
    .resource0_size     (scn_res0_size),
    .resource1_size     (scn_res1_size),
    .resource2_size     (scn_res2_size),
    .resource3_size     (scn_res3_size),
    .music_valid        (scn_music_valid),
    .music_cluster      (scn_music_cluster),
    .music_size         (scn_music_size),
    .track_push         (scn_track_push),
    .track_index        (scn_track_index),
    .track_name         (scn_track_name),
    .track_cluster      (scn_track_cluster),
    .track_size         (scn_track_size),
    .sector_req         (scn_sec_req),
    .sector_lba         (scn_sec_lba),
    .sector_busy        (scn_sec_busy),
    .sector_valid       (scn_sec_valid),
    .sector_byte        (scn_sec_byte),
    .sector_byte_index  (scn_sec_byte_index),
    .sector_done        (scn_sec_done),
    .sector_error       (scn_sec_error)
);

track_list u_track_list (
    .clk            (clk),
    .rst            (rst),
    .clear          (scan_start_pulse),
    .push           (scn_track_push),
    .push_index     (scn_track_index),
    .push_name      (scn_track_name),
    .push_cluster   (scn_track_cluster),
    .push_size      (scn_track_size),
    .valid_mask     (track_valid_mask),
    .track_count    (track_count),
    .lookup_req     (track_lookup_req),
    .lookup_index   (track_lookup_index),
    .lookup_valid   (track_lookup_valid),
    .lookup_name    (track_lookup_name),
    .lookup_cluster (track_lookup_cluster),
    .lookup_size    (track_lookup_size)
);

track_controller u_track_controller (
    .clk                (clk),
    .rst                (rst),
    .enable             (all_resident && scan_done_lvl),
    .valid_mask         (track_valid_mask),
    .track_count        (track_count),
    .cmd_prev           (track_cmd_prev),
    .cmd_next           (track_cmd_next),
    .seek_req           (seek_req_c),
    .seek_fwd           (seek_fwd_c),
    .bytes_consumed     (wav_bytes_consumed),
    .player_start_sector(wav_start_sector),
    .lookup_req         (track_lookup_req),
    .lookup_index       (track_lookup_index),
    .lookup_valid       (track_lookup_valid),
    .lookup_name        (track_lookup_name),
    .lookup_cluster     (track_lookup_cluster),
    .lookup_size        (track_lookup_size),
    .player_busy        (wav_play_busy),
    .player_finish      (wav_play_finish),
    .player_error       (wav_play_error),
    .player_start       (track_player_start),
    .player_stop        (track_player_stop),
    .player_size        (track_player_size),
    .sector_idle        (!wav_chain_m_req && !(sec_grant_valid && sec_grant == 2'd2)),
    .chain_load_start   (track_chain_load),
    .chain_start_cluster(track_chain_cluster),
    .playlist_active    (playlist_active),
    .current_index      (current_track_index),
    .current_name       (current_track_name)
);

fat32_chain_reader u_chain(
    .clk            (clk),
    .rst            (rst),

    .load_start     (load_start_pulse),
    .start_cluster  (load_cluster),

    .fat_start_lba  (scn_fat_start),
    .data_start_lba (scn_data_start),
    .max_cluster    (scn_max_cluster),
    .spc            (scn_spc),

    .bmp_req        (bmp_sec_read),
    .bmp_k          (bmp_sec_addr),

    .to_bmp_data    (chain_to_bmp_data),
    .to_bmp_valid   (chain_to_bmp_valid),
    .to_bmp_end     (chain_to_bmp_end),
    .to_bmp_error   (chain_to_bmp_error),

    .sd_req         (chain_m_req),
    .sd_addr        (chain_m_addr),
    .sd_data        (sd_sec_read_data),
    .sd_valid       ((sec_grant==2'd1) && sd_sec_read_data_valid),
    .sd_end         ((sec_grant==2'd1) && sd_sec_read_end)
);

// ---- SD 读通道三源仲裁 ----
sec_channel_arbiter u_sec_arb(
    .clk        (clk),
    .rst        (rst),
    .scan_req   (scn_read_lvl),
    .pic_req    (chain_m_req),
    .wav_req    (wav_chain_m_req),
    .wav_allowed(all_resident),
    .sec_end    (sd_sec_read_end),
    .sec_timeout(sd_read_timeout_pulse),
    .grant      (sec_grant),
    .grant_valid(sec_grant_valid)
);

// ---- WAV 专用簇链翻译（bmp 侧步骤3接 wav_stream_player）----
fat32_chain_reader u_wav_chain(
    .clk            (clk),
    .rst            (rst),

    .load_start     (wav_load_start),
    .start_cluster  (track_chain_cluster),

    .fat_start_lba  (scn_fat_start),
    .data_start_lba (scn_data_start),
    .max_cluster    (scn_max_cluster),
    .spc            (scn_spc),

    .bmp_req        (wav_pcreq),
    .bmp_k          (wav_pck),

    .to_bmp_data    (wav_chain_data),
    .to_bmp_valid   (wav_chain_valid),
    .to_bmp_end     (wav_chain_end),
    .to_bmp_error   (wav_chain_error),

    .sd_req         (wav_chain_m_req),
    .sd_addr        (wav_chain_m_addr),
    .sd_data        (sd_sec_read_data),
    .sd_valid       ((sec_grant==2'd2) && sd_sec_read_data_valid),
    .sd_end         ((sec_grant==2'd2) && sd_sec_read_end)
);

// ---- WAV 流式播放器（写侧连 wav chain，读侧在 audio_mclk 域）----
wav_stream_player u_wav_player(
    .wr_clk         (clk),
    .wr_rst_n       (~rst),
    .play_start     (track_player_start),
    .play_stop      (track_player_stop),
    .file_size_bytes(track_player_size),
    .start_sector   (wav_start_sector),
    .bytes_consumed (wav_bytes_consumed),
    .play_busy      (wav_play_busy),
    .source_done    (wav_source_done),
    .play_finish    (wav_play_finish),
    .play_error     (wav_play_error),

    .chain_req      (wav_pcreq),
    .chain_k        (wav_pck),
    .chain_data     (wav_chain_data),
    .chain_valid    (wav_chain_valid),
    .chain_end      (wav_chain_end),
    .chain_error    (wav_chain_error),

    .rd_clk         (video_clk),
    .rd_rst_n       (~rst),
    .sample_tick    (audio_tick),
    .sample_out     (wav_pcm),
    .sample_valid   (wav_pcm_valid),
    .sample_ready   (1'b1),

    .sample_counter (),
    .stream_active  (),
    .stream_end     (),
    .buffer_low     ()
);

assign wav_playing = playlist_active;

bmp_read bmp_read_m0(
    .clk                    (clk),
    .rst                    (rst),
    .ready                  (bmp_ready),

    .scan_start             (1'b0),
    .scan_start_sector      (SCAN_START_SECTOR),
    .scan_max_sector        (SCAN_MAX_SECTOR),
    .scan_target_count      (SCAN_TARGET_COUNT),
    .scan_done              (),
    .scan_found_valid       (),
    .scan_found_sector      (),
    .scan_found_total       (),

    .load_start             (load_start_pulse),
    .load_sector            (32'd0),
    .load_file_size         (file_size_lut(load_idx)),

    .sd_init_done           (sd_init_done),
    .state_code             (state_code),
    .bmp_width              (bmp_width),
    .bmp_height             (bmp_height),
    .active_width           (bmp_active_width),
    .active_height          (bmp_active_height),
    .active_offset_x        (bmp_active_offset_x),
    .active_offset_y        (bmp_active_offset_y),
    .active_pixel_count     (bmp_active_pixel_count),
    .write_req              (bmp_write_req),
    .write_req_ack          (wr_ack_sync),
    .sd_sec_read            (bmp_sec_read),
    .sd_sec_read_addr       (bmp_sec_addr),
    .sd_sec_read_data       (bmp_sec_data),
    .sd_sec_read_data_valid (bmp_sec_valid),
    .sd_sec_read_end        (bmp_sec_end),
    .sd_sec_read_error      (bmp_sec_error),
    .bmp_data_wr_en         (bmp_data_wr_en),
    .bmp_data               (bmp_data),
    .load_error_pulse       (bmp_load_error),
    .load_complete_pulse    (bmp_load_complete)
);

sd_card_top sd_card_top_m0(
    .clk                    (clk),
    .rst                    (rst),
    .SD_nCS                 (SD_nCS),
    .SD_DCLK                (SD_DCLK),
    .SD_MOSI                (SD_MOSI),
    .SD_MISO                (SD_MISO),
    .sd_init_done           (sd_init_done),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .sd_sec_read_abort      (sd_read_abort_pulse),
    .sd_sec_write           (1'b0),
    .sd_sec_write_addr      (32'd0),
    .sd_sec_write_data      (),
    .sd_sec_write_data_req  (),
    .sd_sec_write_end       ()
);

endmodule

module key_press_debounce #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,    // 默认：松开=1，按下=0
    output reg  press_pulse
);

localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

reg button_sync0;
reg button_sync1;
reg button_stable;
reg [31:0] cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        button_sync0  <= 1'b1;
        button_sync1  <= 1'b1;
        button_stable <= 1'b1;
        cnt           <= 32'd0;
        press_pulse   <= 1'b0;
    end else begin
        button_sync0 <= button_in;
        button_sync1 <= button_sync0;
        press_pulse  <= 1'b0;

        if (button_sync1 == button_stable) begin
            cnt <= 32'd0;
        end else begin
            if (cnt >= DEBOUNCE_CYCLES - 1) begin
                if (button_stable && !button_sync1)
                    press_pulse <= 1'b1;
                button_stable <= button_sync1;
                cnt           <= 32'd0;
            end else begin
                cnt <= cnt + 32'd1;
            end
        end
    end
end

endmodule
