`timescale 1ns / 1ps
// ============================================================================
/*
    File        : fat32_chain_reader.v
    Description : FAT32 簇链翻译垫片
                  bmp_read 喂 load_sector=0 后，其扇区地址即“文件内相对扇区号 k”。
                  本模块把 k 按 FAT 簇链翻译成真实物理 LBA：
                    目标链位置 = k >> spc_shift，簇内扇区 = k & (spc-1)
                    跨簇时读 FAT 表取下一簇，缓存 1 个 FAT 扇区
                    物理 LBA = data_start + (簇-2)*spc + 簇内扇区
                  坏链（越界/提前 EOC/自循环）向上报错。
    Author      : Anlu
*/
// ============================================================================

module fat32_chain_reader (
    input  wire        clk,
    input  wire        rst,

    // 加载控制
    input  wire        load_start,
    input  wire [31:0] start_cluster,

    // 几何参数（扫描器输出）
    input  wire [31:0] fat_start_lba,
    input  wire [31:0] data_start_lba,
    input  wire [31:0] max_cluster,
    input  wire [7:0]  spc,

    // bmp_read 侧：请求 + 文件内相对扇区 k
    input  wire        bmp_req,
    input  wire [31:0] bmp_k,

    // 到 bmp_read：返回数据
    output reg  [7:0]  to_bmp_data,
    output reg         to_bmp_valid,
    output reg         to_bmp_end,
    output reg         to_bmp_error,

    // sd_card_top 侧：发起物理单块读
    output reg         sd_req,
    output reg  [31:0] sd_addr,
    input  wire [7:0]  sd_data,
    input  wire        sd_valid,
    input  wire        sd_end
);

    localparam [3:0]
        C_IDLE      = 4'd0,
        C_PREP      = 4'd1,
        C_FAT_REQ   = 4'd2,
        C_FAT_WAIT  = 4'd3,
        C_FAT_DONE  = 4'd4,
        C_DATA_REQ  = 4'd5,
        C_DATA_WAIT = 4'd6,
        C_DATA_END  = 4'd7,
        C_ERR       = 4'd8,
        C_PREP_W    = 4'd9;

    reg [3:0]  state;
    reg [7:0]  fat_buf [0:511];

    reg [31:0] fat_start_r;
    reg [31:0] data_start_r;
    reg [31:0] max_cluster_r;
    reg [7:0]  spc_r;
    reg [2:0]  spc_shift_r;

    reg [31:0] cur_cluster;
    reg [31:0] cur_chain_pos;
    reg [31:0] cluster_base_q;

    reg        cache_valid;
    reg [31:0] cached_fat_lba;
    reg [8:0]  sd_byte_cnt;

    function [2:0] spc_to_shift;
        input [7:0] value;
        begin
            case (value)
                8'd1:   spc_to_shift = 3'd0;
                8'd2:   spc_to_shift = 3'd1;
                8'd4:   spc_to_shift = 3'd2;
                8'd8:   spc_to_shift = 3'd3;
                8'd16:  spc_to_shift = 3'd4;
                8'd32:  spc_to_shift = 3'd5;
                8'd64:  spc_to_shift = 3'd6;
                8'd128: spc_to_shift = 3'd7;
                default: spc_to_shift = 3'd3;
            endcase
        end
    endfunction

    function [31:0] fat_le32;
        input integer offset;
        begin
            fat_le32 = {fat_buf[offset+3], fat_buf[offset+2],
                        fat_buf[offset+1], fat_buf[offset]};
        end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state           <= C_IDLE;
            fat_start_r     <= 32'd0;
            data_start_r    <= 32'd0;
            max_cluster_r   <= 32'd0;
            spc_r           <= 8'd8;
            spc_shift_r     <= 3'd3;
            cur_cluster     <= 32'd0;
            cur_chain_pos   <= 32'd0;
            cache_valid     <= 1'b0;
            cached_fat_lba  <= 32'd0;
            sd_byte_cnt     <= 9'd0;
            sd_req          <= 1'b0;
            sd_addr         <= 32'd0;
            to_bmp_data     <= 8'd0;
            to_bmp_valid    <= 1'b0;
            to_bmp_end      <= 1'b0;
            to_bmp_error    <= 1'b0;
        end else begin
            to_bmp_valid <= 1'b0;
            to_bmp_end   <= 1'b0;
            to_bmp_error <= 1'b0;
            sd_req       <= 1'b0;

            cluster_base_q <= data_start_r + ((cur_cluster - 32'd2) << spc_shift_r);

            if (load_start) begin
                fat_start_r   <= fat_start_lba;
                data_start_r  <= data_start_lba;
                max_cluster_r <= max_cluster;
                spc_r         <= spc;
                spc_shift_r   <= spc_to_shift(spc);
                cur_cluster   <= start_cluster;
                cur_chain_pos <= 32'd0;
                cache_valid   <= 1'b0;
                state         <= C_PREP_W;
            end else case (state)
                C_IDLE: begin
                    state <= C_IDLE;
                end

                C_PREP_W: begin
                    state <= C_PREP;
                end

                C_PREP: begin
                    if (!bmp_req) begin
                        state <= C_PREP;
                    end else begin : prep_calc
                        reg [31:0] target_pos;
                        reg [31:0] sec_in;
                        reg [31:0] need_fat_lba;
                        reg [31:0] phys;
                        begin
                            target_pos = bmp_k >> spc_shift_r;
                            sec_in     = bmp_k & ({24'd0, spc_r} - 32'd1);

                            if (cur_chain_pos < target_pos) begin
                                need_fat_lba = fat_start_r + (cur_cluster >> 7);
                                if (cache_valid && cached_fat_lba == need_fat_lba) begin
                                    state <= C_FAT_DONE;
                                end else begin
                                    sd_addr <= need_fat_lba;
                                    state   <= C_FAT_REQ;
                                end
                            end else begin
                                phys = cluster_base_q + sec_in;
                                sd_addr <= phys;
                                state   <= C_DATA_REQ;
                            end
                        end
                    end
                end

                C_FAT_REQ: begin
                    sd_req      <= 1'b1;
                    sd_byte_cnt <= 9'd0;
                    state       <= C_FAT_WAIT;
                end

                C_FAT_WAIT: begin
                    sd_req <= 1'b1;
                    if (sd_valid) begin
                        fat_buf[sd_byte_cnt] <= sd_data;
                        sd_byte_cnt <= sd_byte_cnt + 9'd1;
                    end
                    if (sd_end) begin
                        sd_req         <= 1'b0;
                        cache_valid    <= 1'b1;
                        cached_fat_lba <= sd_addr;
                        state          <= C_FAT_DONE;
                    end
                end

                C_FAT_DONE: begin : parse_fat
                    reg [8:0]  fat_off;
                    reg [31:0] entry;
                    begin
                        fat_off = {cur_cluster[6:0], 2'b00};
                        entry   = fat_le32(fat_off) & 32'h0FFFFFFF;

                        if (entry >= 32'h0FFFFFF8) begin
                            // 提前 EOC：链比预期短
                            state <= C_ERR;
                        end else if (entry < 32'd2 || entry >= max_cluster_r) begin
                            state <= C_ERR;
                        end else if ((cur_chain_pos + 32'd1) >= max_cluster_r) begin
                            // 链位置越界（自循环保护）
                            state <= C_ERR;
                        end else begin
                            cur_cluster   <= entry;
                            cur_chain_pos <= cur_chain_pos + 32'd1;
                            state         <= C_PREP_W;
                        end
                    end
                end

                C_DATA_REQ: begin
                    sd_req <= 1'b1;
                    state  <= C_DATA_WAIT;
                end

                C_DATA_WAIT: begin
                    sd_req       <= 1'b1;
                    to_bmp_valid <= sd_valid;
                    to_bmp_data  <= sd_data;
                    if (sd_end) begin
                        sd_req     <= 1'b0;
                        to_bmp_end <= 1'b1;
                        state      <= C_DATA_END;
                    end
                end

                C_DATA_END: begin
                    state <= C_PREP;
                end

                C_ERR: begin
                    to_bmp_error <= 1'b1;
                    state        <= C_IDLE;
                end

                default: state <= C_IDLE;
            endcase
        end
    end

endmodule
