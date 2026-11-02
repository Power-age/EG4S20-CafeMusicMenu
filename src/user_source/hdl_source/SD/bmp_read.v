module bmp_read(
    input                       clk,
    input                       rst,
    output                      ready,

    // 上电扫描：从 scan_start_sector 开始，顺序寻找前 scan_target_count 张 BMP
    input                       scan_start,
    input  [31:0]               scan_start_sector,
    input  [31:0]               scan_max_sector,
    input  [2:0]                scan_target_count,
    output reg                  scan_done,
    output reg                  scan_found_valid,
    output reg [31:0]           scan_found_sector,
    output reg [2:0]            scan_found_total,

    // 按指定扇区加载一张图到 SDRAM
    input                       load_start,
    input  [31:0]               load_sector,
    input  [31:0]               load_file_size,

    input                       sd_init_done,
    output reg [3:0]            state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,

    output reg [15:0]           active_width,
    output reg [15:0]           active_height,
    output reg [15:0]           active_offset_x,
    output reg [15:0]           active_offset_y,
    output reg [20:0]           active_pixel_count,

    output reg                  write_req,
    input                       write_req_ack,

    output reg                  sd_sec_read,
    output reg [31:0]           sd_sec_read_addr,
    input  [7:0]                sd_sec_read_data,
    input                       sd_sec_read_data_valid,
    input                       sd_sec_read_end,
    input                       sd_sec_read_error,

    output reg                  bmp_data_wr_en,
    output reg [23:0]           bmp_data,
    output reg                  load_error_pulse,
    output reg                  load_complete_pulse
);

localparam [4:0] ST_IDLE       = 5'd0;
localparam [4:0] ST_SCAN       = 5'd1;
localparam [4:0] ST_LOAD_HDR   = 5'd2;
localparam [4:0] ST_HDR_PREP   = 5'd3;
localparam [4:0] ST_HDR_STRIDE = 5'd4;
localparam [4:0] ST_HDR_IMAGE  = 5'd5;
localparam [4:0] ST_HDR_RANGE  = 5'd6;
localparam [4:0] ST_HDR_FIT_PREP  = 5'd7;
localparam [4:0] ST_HDR_FIT_RUN   = 5'd8;
localparam [4:0] ST_HDR_FIT_APPLY = 5'd9;
localparam [4:0] ST_HDR_APPLY     = 5'd10;
localparam [4:0] ST_HDR_DECIDE    = 5'd11;
localparam [4:0] ST_LOAD_WAIT     = 5'd12;
localparam [4:0] ST_LOAD_DATA     = 5'd13;
localparam [4:0] ST_UP_PREP       = 5'd14;
localparam [4:0] ST_UP_READ       = 5'd15;
localparam [4:0] ST_UP_SCALE      = 5'd16;
localparam [4:0] ST_UP_REPEAT     = 5'd17;
localparam [4:0] ST_UP_EMIT       = 5'd18;
localparam [4:0] ST_UP_FETCH      = 5'd19;

localparam [31:0] BMP_MIN_PIXEL_OFFSET = 32'd54;

reg [4:0]  state;
reg [9:0]  rd_cnt;

reg [7:0]  header_0;
reg [7:0]  header_1;
reg [31:0] file_len;
reg [31:0] pixel_offset;
reg [31:0] dib_header_size;
reg [31:0] width;
reg [31:0] height;
reg [15:0] planes;
reg [15:0] bit_count;
reg [31:0] compression;
reg [31:0] image_size;

reg [31:0] scan_sector;
reg [31:0] load_sector_latched;
reg [31:0] load_file_size_latched;
reg [31:0] bmp_len_cnt;
reg [17:0] bmp_row_byte_cnt;
reg [1:0]  source_pixel_byte_idx;
reg [23:0] source_pixel_data;
reg [15:0] scale_out_x;
reg [15:0] scale_out_y;
reg [31:0] scale_x_acc;
reg [31:0] scale_y_acc;
reg        scale_row_emit;

reg [15:0] up_source_y;
reg [35:0] up_row_calc_acc;
reg [15:0] up_out_y;
reg [15:0] up_raw_x;
reg [15:0] up_emit_x;
reg [15:0] up_emit_src_x;
reg [8:0]  up_sector_byte_cnt;
reg [8:0]  up_sector_start_offset;
reg [17:0] up_row_read_byte_cnt;
reg [1:0]  up_pixel_byte_idx;
reg [15:0] up_pixel_data;
reg [31:0] up_scale_x_acc;
reg [31:0] up_scale_y_acc;

reg        fit_wide;
reg [31:0] fit_scale_base;
reg [31:0] fit_scale_step;
reg [31:0] fit_calc_acc;
reg [15:0] fit_calc_count;
reg [15:0] fit_calc_limit;
reg [15:0] fit_calc_out;

reg        header_is_scan;
reg        header_basic_ok;
reg        header_match;
reg [17:0] source_row_bytes;
reg [17:0] source_row_stride;
reg [33:0] source_image_bytes;
reg [35:0] pixel_data_end_sum;
reg [31:0] pixel_data_end;
reg [31:0] file_sector_count;
reg [20:0] output_pixel_count;
reg        load_finish_pending;

wire bmp_dimension_bits_ok;
wire source_fits_target;
wire source_dimension_supported;
wire upscale_needed;
wire [31:0] target_width;
wire [31:0] target_height;
wire [31:0] active_width_32;
wire [31:0] active_height_32;
wire [31:0] source_width_32;
wire [31:0] source_height_32;
wire [35:0] pixel_data_end_sum_next;
wire stream_pixel_byte;
wire source_row_end_byte;
wire source_pixel_complete;
wire scale_col_emit;
wire scale_frame_done;
wire [31:0] scale_x_acc_next;
wire [31:0] scale_y_acc_next;
wire [31:0] up_scale_x_acc_next;
wire [31:0] up_scale_y_acc_next;
wire [35:0] up_row_start_calc;
wire [31:0] up_row_start_sector;
wire up_sector_past_start;
wire up_row_byte_active;
wire up_row_read_done;
wire up_row_wr_en;
wire [9:0] up_row_wr_addr;
wire [23:0] up_row_wr_data;
wire up_row_rd_en;
wire [9:0] up_row_rd_addr;
wire [23:0] up_row_rd_data;
wire [31:0] aspect_lhs;
wire [31:0] aspect_rhs;
reg  [31:0] aspect_lhs_q;   // 阶段 0.5 步骤 B：乘积打一拍，拆开乘法与比较
reg  [31:0] aspect_rhs_q;
wire [31:0] fit_calc_acc_next;
wire fit_calc_pending;
wire fit_calc_emit;
wire fit_calc_done;
wire [15:0] fit_calc_size_clamped;
wire [15:0] fit_wide_offset_y;
wire [15:0] fit_tall_offset_x;
wire [20:0] fit_wide_pixel_count;
wire [20:0] fit_tall_pixel_count;
wire [31:0] next_scan_sector_if_match;
wire [31:0] next_scan_sector_if_miss;
wire output_pixel_written;

assign ready = (state == ST_IDLE);
assign target_width = {16'd0, bmp_width};
assign target_height = {16'd0, bmp_height};
assign active_width_32 = {16'd0, active_width};
assign active_height_32 = {16'd0, active_height};
assign source_width_32 = {16'd0, width[15:0]};
assign source_height_32 = {16'd0, height[15:0]};
assign bmp_dimension_bits_ok = (width[31:16] == 16'd0) && (height[31:16] == 16'd0);
assign source_fits_target = (width <= target_width) && (height <= target_height);
assign source_dimension_supported = source_fits_target || (width > target_width) || (height > target_height);
// 2026-10-31：按素材规格（宽高均 >= 640x480）关闭上采样通路（该通路的寄存器组会残留 ps 级 hold 违例）
assign upscale_needed = 1'b0;
assign pixel_data_end_sum_next = {4'd0, pixel_offset} + {2'd0, source_image_bytes};
assign stream_pixel_byte = (bmp_len_cnt >= pixel_offset) && (bmp_len_cnt < pixel_data_end);
assign source_row_end_byte = (bmp_row_byte_cnt == source_row_stride - 18'd1);
assign source_pixel_complete = stream_pixel_byte && (bmp_row_byte_cnt < source_row_bytes) && (source_pixel_byte_idx == 2'd2);
assign scale_x_acc_next = scale_x_acc + fit_scale_step;
assign scale_y_acc_next = scale_y_acc + fit_scale_step;
assign scale_col_emit = scale_row_emit && (scale_x_acc_next >= fit_scale_base) && (scale_out_x < active_width);
assign scale_frame_done = (scale_out_y >= active_height);
assign up_scale_x_acc_next = up_scale_x_acc + source_width_32;
assign up_scale_y_acc_next = up_scale_y_acc + source_height_32;
assign up_row_start_calc = up_row_calc_acc;
assign up_row_start_sector = load_sector_latched + {9'd0, up_row_start_calc[31:9]};
assign up_sector_past_start = (sd_sec_read_addr != up_row_start_sector) || (up_sector_byte_cnt >= up_sector_start_offset);
assign up_row_byte_active = up_sector_past_start && (up_row_read_byte_cnt < source_row_stride);
assign up_row_read_done = (up_row_read_byte_cnt >= source_row_stride);
assign up_row_wr_en = (state == ST_UP_READ) && sd_sec_read_data_valid && up_row_byte_active && (up_row_read_byte_cnt < source_row_bytes) && (up_pixel_byte_idx == 2'd2);
assign up_row_wr_addr = up_raw_x[9:0];
assign up_row_wr_data = {sd_sec_read_data, up_pixel_data[15:0]};
assign up_row_rd_en = (state == ST_UP_SCALE) || (state == ST_UP_FETCH);
assign up_row_rd_addr = up_emit_src_x[9:0];


assign output_pixel_written = bmp_data_wr_en;
// 2026/10/21 阶段 0.5：原实现是 32 位维度做 64x64 乘法再截断，
// TD 用 MULT18 + 4 级加法器拼出，路径 12.891ns 且带 width[24] 高位。
// 实际图片尺寸 <= 8192、缓冲仅 640x480，故把维度饱和到 16 位后做 16x16 乘法，
// 语义在正常图片上与原来完全一致（超过 65535 的尺寸饱和为 0xFFFF，不会退化成 0）。
wire [15:0] width16_aspect  = (width[31:16]  != 16'd0) ? 16'hFFFF : width[15:0];
wire [15:0] height16_aspect = (height[31:16] != 16'd0) ? 16'hFFFF : height[15:0];
assign aspect_lhs = width16_aspect  * bmp_height;
assign aspect_rhs = height16_aspect * bmp_width;
assign fit_calc_acc_next = fit_calc_acc + fit_scale_step;
assign fit_calc_pending = (fit_calc_acc >= fit_scale_base);
assign fit_calc_emit = (fit_calc_acc_next >= fit_scale_base);
assign fit_calc_done = (fit_calc_count >= fit_calc_limit) && !fit_calc_pending;
assign fit_calc_size_clamped = (fit_calc_out == 16'd0) ? 16'd1 : fit_calc_out;
assign fit_wide_offset_y = (bmp_height > fit_calc_size_clamped) ? ((bmp_height - fit_calc_size_clamped) >> 1) : 16'd0;
assign fit_tall_offset_x = (bmp_width > fit_calc_size_clamped) ? ((bmp_width - fit_calc_size_clamped) >> 1) : 16'd0;
assign fit_wide_pixel_count = {5'd0, bmp_width} * {5'd0, fit_calc_size_clamped};
assign fit_tall_pixel_count = {5'd0, fit_calc_size_clamped} * {5'd0, bmp_height};
assign next_scan_sector_if_match = scan_sector + file_sector_count;
assign next_scan_sector_if_miss  = scan_sector + 32'd1;

`ifdef BMP_ROW_MEM_SIM
reg [23:0] up_row_sim_mem [0:1023];
reg [23:0] up_row_sim_q;
always @(posedge clk) begin
    if (up_row_wr_en)
        up_row_sim_mem[up_row_wr_addr] <= up_row_wr_data;
    if (up_row_rd_en)
        up_row_sim_q <= up_row_sim_mem[up_row_rd_addr];
    else
        up_row_sim_q <= up_row_sim_q;
end
assign up_row_rd_data = up_row_sim_q;
`else
EG_LOGIC_BRAM #(
    .DATA_WIDTH_A(24),
    .ADDR_WIDTH_A(10),
    .DATA_DEPTH_A(1024),
    .DATA_WIDTH_B(24),
    .ADDR_WIDTH_B(10),
    .DATA_DEPTH_B(1024),
    .MODE("PDPW"),
    .REGMODE_A("NOREG"),
    .REGMODE_B("NOREG"),
    .WRITEMODE_A("NORMAL"),
    .WRITEMODE_B("NORMAL"),
    .RESETMODE("SYNC"),
    .DEBUGGABLE("NO"),
    .PACKABLE("NO"),
    .FORCE_KEEP("OFF"),
    .INIT_FILE("NONE"),
    .FILL_ALL("NONE"),
    .IMPLEMENT("9K")
) up_row_mem (
    .dia(up_row_wr_data),
    .addra(up_row_wr_addr),
    .cea(up_row_wr_en),
    .ocea(1'b0),
    .clka(clk),
    .wea(up_row_wr_en),
    .rsta(1'b0),
    .bea(1'b0),
    .dib(24'd0),
    .addrb(up_row_rd_addr),
    .ceb(up_row_rd_en),
    .oceb(1'b0),
    .clkb(clk),
    .web(1'b0),
    .rstb(1'b0),
    .beb(1'b0),
    .doa(),
    .dob(up_row_rd_data)
);
`endif

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rd_cnt <= 10'd0;
    end else if ((state == ST_SCAN) || (state == ST_LOAD_HDR)) begin
        if (sd_sec_read_data_valid)
            rd_cnt <= rd_cnt + 10'd1;
        else if (sd_sec_read_end)
            rd_cnt <= 10'd0;
    end else begin
        rd_cnt <= 10'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        header_0     <= 8'd0;
        header_1     <= 8'd0;
        file_len     <= 32'd0;
        pixel_offset <= 32'd54;
        dib_header_size <= 32'd0;
        width        <= 32'd0;
        height       <= 32'd0;
        planes       <= 16'd0;
        bit_count    <= 16'd0;
        compression  <= 32'd0;
        image_size   <= 32'd0;
    end else if (((state == ST_SCAN) || (state == ST_LOAD_HDR)) && sd_sec_read_data_valid) begin
        case (rd_cnt)
            10'd0 : header_0 <= sd_sec_read_data;
            10'd1 : header_1 <= sd_sec_read_data;

            10'd2 : file_len[7:0] <= sd_sec_read_data;
            10'd3 : file_len[15:8] <= sd_sec_read_data;
            10'd4 : file_len[23:16] <= sd_sec_read_data;
            10'd5 : file_len[31:24] <= sd_sec_read_data;

            10'd10: pixel_offset[7:0] <= sd_sec_read_data;
            10'd11: pixel_offset[15:8] <= sd_sec_read_data;
            10'd12: pixel_offset[23:16] <= sd_sec_read_data;
            10'd13: pixel_offset[31:24] <= sd_sec_read_data;

            10'd14: dib_header_size[7:0] <= sd_sec_read_data;
            10'd15: dib_header_size[15:8] <= sd_sec_read_data;
            10'd16: dib_header_size[23:16] <= sd_sec_read_data;
            10'd17: dib_header_size[31:24] <= sd_sec_read_data;

            10'd18: width[7:0] <= sd_sec_read_data;
            10'd19: width[15:8] <= sd_sec_read_data;
            10'd20: width[23:16] <= sd_sec_read_data;
            10'd21: width[31:24] <= sd_sec_read_data;

            10'd22: height[7:0] <= sd_sec_read_data;
            10'd23: height[15:8] <= sd_sec_read_data;
            10'd24: height[23:16] <= sd_sec_read_data;
            10'd25: height[31:24] <= sd_sec_read_data;

            10'd26: planes[7:0] <= sd_sec_read_data;
            10'd27: planes[15:8] <= sd_sec_read_data;

            10'd28: bit_count[7:0] <= sd_sec_read_data;
            10'd29: bit_count[15:8] <= sd_sec_read_data;

            10'd30: compression[7:0] <= sd_sec_read_data;
            10'd31: compression[15:8] <= sd_sec_read_data;
            10'd32: compression[23:16] <= sd_sec_read_data;
            10'd33: compression[31:24] <= sd_sec_read_data;

            10'd34: image_size[7:0] <= sd_sec_read_data;
            10'd35: image_size[15:8] <= sd_sec_read_data;
            10'd36: image_size[23:16] <= sd_sec_read_data;
            10'd37: image_size[31:24] <= sd_sec_read_data;
            default: ;
        endcase
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        header_basic_ok <= 1'b0;
        header_match <= 1'b0;
        source_row_bytes <= 18'd0;
        source_row_stride <= 18'd0;
        source_image_bytes <= 34'd0;
        pixel_data_end_sum <= 36'd0;
        pixel_data_end <= 32'd0;
        file_sector_count <= 32'd1;
    end else begin
        case (state)
            ST_HDR_PREP: begin
                header_basic_ok <= (header_0 == "B") &&
                                   (header_1 == "M") &&
                                   (dib_header_size == 32'd40) &&
                                   (planes == 16'd1) &&
                                   bmp_dimension_bits_ok &&
                                   (width != 32'd0) &&
                                   (height != 32'd0) &&
                                   source_dimension_supported &&
                                   (bit_count == 16'd24) &&
                                   (compression == 32'd0);
                source_row_bytes <= {2'd0, width[15:0]} + ({2'd0, width[15:0]} << 1);
                file_sector_count <= (file_len == 32'd0) ? 32'd1 : ((file_len + 32'd511) >> 9);
            end
            ST_HDR_STRIDE: begin
                source_row_stride <= (source_row_bytes + 18'd3) & 18'h3FFFC;
            end
            ST_HDR_IMAGE: begin
                source_image_bytes <= {16'd0, source_row_stride} * {18'd0, height[15:0]};
            end
            ST_HDR_RANGE: begin
                pixel_data_end_sum <= pixel_data_end_sum_next;
                pixel_data_end <= pixel_data_end_sum_next[31:0];
            end
            ST_HDR_APPLY: begin
                header_match <= header_basic_ok &&
                                (pixel_offset >= BMP_MIN_PIXEL_OFFSET) &&
                                (file_len >= pixel_offset) &&
                                (pixel_data_end_sum[35:32] == 4'd0) &&
                                (pixel_data_end <= file_len) &&
                                ((image_size == 32'd0) || ({2'd0, image_size} >= source_image_bytes)) &&
                                ((load_file_size_latched == 32'd0) || (load_file_size_latched >= pixel_data_end));
            end
            default: ;
        endcase
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        active_width <= 16'd640;
        active_height <= 16'd480;
        active_offset_x <= 16'd0;
        active_offset_y <= 16'd0;
        active_pixel_count <= 21'd307200;
        fit_wide <= 1'b0;
        aspect_lhs_q <= 32'd0;
        aspect_rhs_q <= 32'd0;
        fit_scale_base <= 32'd480;
        fit_scale_step <= 32'd480;
        fit_calc_acc <= 32'd0;
        fit_calc_count <= 16'd0;
        fit_calc_limit <= 16'd0;
        fit_calc_out <= 16'd0;
    end else begin
        case (state)
            ST_HDR_PREP: begin
                active_width <= bmp_width;
                active_height <= bmp_height;
                active_offset_x <= 16'd0;
                active_offset_y <= 16'd0;
                active_pixel_count <= {5'd0, bmp_width} * {5'd0, bmp_height};
                fit_wide <= 1'b0;
                fit_scale_base <= target_height;
                fit_scale_step <= target_height;
                fit_calc_acc <= 32'd0;
                fit_calc_count <= 16'd0;
                fit_calc_limit <= 16'd0;
                fit_calc_out <= 16'd0;
            end
            ST_HDR_RANGE: begin
                aspect_lhs_q <= aspect_lhs;      // 阶段 0.5 步骤 B：乘积在 RANGE 拍寄存
                aspect_rhs_q <= aspect_rhs;
            end
            ST_HDR_FIT_PREP: begin
                fit_wide <= (aspect_lhs_q > aspect_rhs_q);
                fit_calc_acc <= 32'd0;
                fit_calc_count <= 16'd0;
                fit_calc_out <= 16'd0;
                if (aspect_lhs_q > aspect_rhs_q) begin
                    fit_scale_base <= width;
                    fit_scale_step <= target_width;
                    fit_calc_limit <= height[15:0];
                end else begin
                    fit_scale_base <= height;
                    fit_scale_step <= target_height;
                    fit_calc_limit <= width[15:0];
                end
            end
            ST_HDR_FIT_RUN: begin
                if (!fit_calc_done) begin
                    if (fit_calc_pending) begin
                        fit_calc_acc <= fit_calc_acc - fit_scale_base;
                        fit_calc_out <= fit_calc_out + 16'd1;
                    end else if (fit_calc_count < fit_calc_limit) begin
                        fit_calc_count <= fit_calc_count + 16'd1;
                        if (fit_calc_emit) begin
                            fit_calc_acc <= fit_calc_acc_next - fit_scale_base;
                            fit_calc_out <= fit_calc_out + 16'd1;
                        end else begin
                            fit_calc_acc <= fit_calc_acc_next;
                        end
                    end
                end
            end
            ST_HDR_FIT_APPLY: begin
                if (fit_wide) begin
                    active_width <= bmp_width;
                    active_height <= fit_calc_size_clamped;
                    active_offset_x <= 16'd0;
                    active_offset_y <= fit_wide_offset_y;
                    active_pixel_count <= fit_wide_pixel_count;
                    fit_scale_base <= width;
                    fit_scale_step <= target_width;
                end else begin
                    active_width <= fit_calc_size_clamped;
                    active_height <= bmp_height;
                    active_offset_x <= fit_tall_offset_x;
                    active_offset_y <= 16'd0;
                    active_pixel_count <= fit_tall_pixel_count;
                    fit_scale_base <= height;
                    fit_scale_step <= target_height;
                end
            end
            default: ;
        endcase
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_len_cnt <= 32'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (sd_sec_read_data_valid)
            bmp_len_cnt <= bmp_len_cnt + 32'd1;
    end else begin
        bmp_len_cnt <= 32'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_row_byte_cnt <= 18'd0;
        source_pixel_byte_idx <= 2'd0;
        scale_out_x <= 16'd0;
        scale_out_y <= 16'd0;
        scale_x_acc <= 32'd0;
        scale_y_acc <= 32'd0;
        scale_row_emit <= 1'b0;
    end else if (state == ST_LOAD_WAIT) begin
        bmp_row_byte_cnt <= 18'd0;
        source_pixel_byte_idx <= 2'd0;
        scale_out_x <= 16'd0;
        scale_out_y <= 16'd0;
        scale_x_acc <= 32'd0;
        scale_y_acc <= 32'd0;
        scale_row_emit <= 1'b1;
    end else if (state == ST_LOAD_DATA) begin
        if (sd_sec_read_data_valid && stream_pixel_byte) begin
            if (bmp_row_byte_cnt < source_row_bytes) begin
                if (source_pixel_byte_idx == 2'd2)
                    source_pixel_byte_idx <= 2'd0;
                else
                    source_pixel_byte_idx <= source_pixel_byte_idx + 2'd1;
            end

            if (source_pixel_complete) begin
                if (scale_col_emit) begin
                    if (scale_out_x == active_width - 16'd1)
                        scale_out_x <= 16'd0;
                    else
                        scale_out_x <= scale_out_x + 16'd1;

                    scale_x_acc <= scale_x_acc_next - fit_scale_base;
                end else begin
                    scale_x_acc <= scale_x_acc_next;
                end
            end

            if (source_row_end_byte) begin
                bmp_row_byte_cnt <= 18'd0;
                source_pixel_byte_idx <= 2'd0;
                scale_out_x <= 16'd0;
                scale_x_acc <= 32'd0;

                if (scale_y_acc_next >= fit_scale_base) begin
                    scale_y_acc <= scale_y_acc_next - fit_scale_base;
                    if (scale_out_y < active_height)
                        scale_out_y <= scale_out_y + 16'd1;
                end else begin
                    scale_y_acc <= scale_y_acc_next;
                end

                scale_row_emit <= (scale_y_acc_next >= fit_scale_base) && (scale_out_y < active_height - 16'd1);
            end else begin
                bmp_row_byte_cnt <= bmp_row_byte_cnt + 18'd1;
            end
        end
    end else begin
        bmp_row_byte_cnt <= 18'd0;
        source_pixel_byte_idx <= 2'd0;
        scale_out_x <= 16'd0;
        scale_out_y <= 16'd0;
        scale_x_acc <= 32'd0;
        scale_y_acc <= 32'd0;
        scale_row_emit <= 1'b0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        up_source_y <= 16'd0;
        up_out_y <= 16'd0;
        up_raw_x <= 16'd0;
        up_emit_x <= 16'd0;
        up_emit_src_x <= 16'd0;
        up_sector_byte_cnt <= 9'd0;
        up_sector_start_offset <= 9'd0;
        up_row_read_byte_cnt <= 18'd0;
        up_pixel_byte_idx <= 2'd0;
        up_pixel_data <= 16'd0;
        up_scale_x_acc <= 32'd0;
        up_scale_y_acc <= 32'd0;
    end else begin
        case (state)
            ST_LOAD_WAIT: begin
                if (write_req_ack) begin
                    up_source_y <= 16'd0;
                    up_row_calc_acc <= {4'd0, pixel_offset};
                    up_out_y <= 16'd0;
                    up_raw_x <= 16'd0;
                    up_emit_x <= 16'd0;
                    up_emit_src_x <= 16'd0;
                    up_sector_byte_cnt <= 9'd0;
                    up_sector_start_offset <= 9'd0;
                    up_row_read_byte_cnt <= 18'd0;
                    up_pixel_byte_idx <= 2'd0;
                    up_pixel_data <= 16'd0;
                    up_scale_x_acc <= 32'd0;
                    up_scale_y_acc <= 32'd0;
                end
            end
            default: ;
        endcase
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        source_pixel_data <= 24'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (sd_sec_read_data_valid && stream_pixel_byte && (bmp_row_byte_cnt < source_row_bytes)) begin
            case (source_pixel_byte_idx)
                2'd0: source_pixel_data[7:0] <= sd_sec_read_data;
                2'd1: source_pixel_data[15:8] <= sd_sec_read_data;
                2'd2: source_pixel_data[23:16] <= sd_sec_read_data;
                default: ;
            endcase
        end
    end else begin
        source_pixel_data <= 24'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        output_pixel_count <= 21'd0;
    end else if (state == ST_LOAD_WAIT) begin
        output_pixel_count <= 21'd0;
    end else if (output_pixel_written && (output_pixel_count < active_pixel_count)) begin
        output_pixel_count <= output_pixel_count + 21'd1;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_data_wr_en <= 1'b0;
        bmp_data       <= 24'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (sd_sec_read_data_valid && source_pixel_complete && scale_col_emit) begin
            bmp_data_wr_en <= 1'b1;
            bmp_data       <= {sd_sec_read_data, source_pixel_data[15:0]};
        end else begin
            bmp_data_wr_en <= 1'b0;
        end
    end else if (state == ST_UP_EMIT) begin
        bmp_data_wr_en <= 1'b1;
        bmp_data       <= up_row_rd_data;
    end else begin
        bmp_data_wr_en <= 1'b0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state             <= ST_IDLE;
        state_code        <= 4'd0;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 3'd0;
        scan_sector       <= 32'd0;
        load_sector_latched <= 32'd0;
        load_file_size_latched <= 32'd0;
        header_is_scan    <= 1'b0;
        load_error_pulse  <= 1'b0;
        load_complete_pulse <= 1'b0;
        load_finish_pending <= 1'b0;
    end else if (!sd_init_done) begin
        state             <= ST_IDLE;
        state_code        <= 4'd0;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 3'd0;
        scan_sector       <= 32'd0;
        load_sector_latched <= 32'd0;
        load_file_size_latched <= 32'd0;
        header_is_scan    <= 1'b0;
        load_error_pulse  <= 1'b0;
        load_complete_pulse <= 1'b0;
        load_finish_pending <= 1'b0;
    end else begin
        scan_found_valid <= 1'b0;
        load_error_pulse <= 1'b0;
        load_complete_pulse <= 1'b0;
        if (load_finish_pending) begin
            if (output_pixel_count == active_pixel_count)
                load_complete_pulse <= 1'b1;
            else
                load_error_pulse <= 1'b1;
            load_finish_pending <= 1'b0;
        end

        case (state)
            ST_IDLE: begin
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;

                if (scan_start) begin
                    scan_done        <= 1'b0;
                    scan_found_total <= 3'd0;
                    scan_sector      <= scan_start_sector;
                    sd_sec_read_addr <= scan_start_sector;
                    state            <= ST_SCAN;
                end else if (load_start) begin
                    load_sector_latched <= load_sector;
                    load_file_size_latched <= load_file_size;
                    sd_sec_read_addr    <= load_sector;
                    state               <= ST_LOAD_HDR;
                end
            end

            ST_SCAN: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read    <= 1'b0;
                    header_is_scan <= 1'b1;
                    state          <= ST_HDR_PREP;
                end
            end

            ST_LOAD_HDR: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read    <= 1'b0;
                    header_is_scan <= 1'b0;
                    state          <= ST_HDR_PREP;
                end else if (sd_sec_read_error) begin
                    sd_sec_read       <= 1'b0;
                    header_is_scan     <= 1'b0;
                    load_error_pulse  <= 1'b1;
                    state              <= ST_IDLE;
                end
            end

            ST_HDR_PREP: begin
                state_code <= 4'd2;
                state      <= ST_HDR_STRIDE;
            end

            ST_HDR_STRIDE: begin
                state_code <= 4'd2;
                state      <= ST_HDR_IMAGE;
            end

            ST_HDR_IMAGE: begin
                state_code <= 4'd2;
                state      <= ST_HDR_RANGE;
            end

            ST_HDR_RANGE: begin
                state_code <= 4'd2;
                state      <= header_basic_ok ? ST_HDR_FIT_PREP : ST_HDR_APPLY;
            end

            ST_HDR_FIT_PREP: begin
                state_code <= 4'd2;
                state      <= ST_HDR_FIT_RUN;
            end

            ST_HDR_FIT_RUN: begin
                state_code <= 4'd2;
                if (fit_calc_done)
                    state <= ST_HDR_FIT_APPLY;
            end

            ST_HDR_FIT_APPLY: begin
                state_code <= 4'd2;
                state      <= ST_HDR_APPLY;
            end

            ST_HDR_APPLY: begin
                state_code <= 4'd2;
                state      <= ST_HDR_DECIDE;
            end

            ST_HDR_DECIDE: begin
                state_code <= 4'd2;
                if (header_is_scan) begin
                    if (header_match) begin
                        scan_found_valid  <= 1'b1;
                        scan_found_sector <= scan_sector;
                        scan_found_total  <= scan_found_total + 3'd1;

                        if ((scan_found_total + 3'd1 >= scan_target_count) || (next_scan_sector_if_match > scan_max_sector)) begin
                            scan_done        <= 1'b1;
                            state            <= ST_IDLE;
                            sd_sec_read_addr <= next_scan_sector_if_match;
                            scan_sector      <= next_scan_sector_if_match;
                        end else begin
                            sd_sec_read_addr <= next_scan_sector_if_match;
                            scan_sector      <= next_scan_sector_if_match;
                            state            <= ST_SCAN;
                        end
                    end else begin
                        if (scan_sector >= scan_max_sector) begin
                            scan_done <= 1'b1;
                            state     <= ST_IDLE;
                        end else begin
                            sd_sec_read_addr <= next_scan_sector_if_miss;
                            scan_sector      <= next_scan_sector_if_miss;
                            state            <= ST_SCAN;
                        end
                    end
                end else begin
                    if (header_match) begin
                        write_req        <= 1'b1;
                        sd_sec_read_addr <= load_sector_latched;
                        state            <= ST_LOAD_WAIT;
                    end else begin
                        load_error_pulse <= 1'b1;
                        state <= ST_IDLE;
                    end
                end
            end

            ST_LOAD_WAIT: begin
                state_code <= 4'd3;
                if (write_req_ack) begin
                    write_req <= 1'b0;
                    state     <= ST_LOAD_DATA;   // 2026-10-31 上采样已移除
                end
            end

            ST_LOAD_DATA: begin
                state_code  <= 4'd4;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (scale_frame_done || (bmp_len_cnt >= pixel_data_end)) begin
                        load_finish_pending <= 1'b1;
                        state <= ST_IDLE;
                    end else begin
                        sd_sec_read_addr <= sd_sec_read_addr + 32'd1;
                    end
                end else if (sd_sec_read_error) begin
                    sd_sec_read      <= 1'b0;
                    load_error_pulse <= 1'b1;
                    state            <= ST_IDLE;
                end
            end

            default: begin
                state       <= ST_IDLE;
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;
            end
        endcase
    end
end

endmodule
