`timescale 1ns / 1ps
module wav_stream_player #(
    parameter integer ADDR_WIDTH = 12,
    parameter integer SAMPLES_PER_SECTOR = 256,
    parameter integer GUARD_SAMPLES = 64
) (
    input  wire        wr_clk,
    input  wire        wr_rst_n,
    input  wire        play_start,
    input  wire        play_stop,
    input  wire [31:0] file_size_bytes,
    input  wire [31:0] start_sector,
    output wire [31:0] bytes_consumed,
    output reg         play_busy,
    output reg         source_done,
    output reg         play_finish,
    output reg         play_error,
    output reg         chain_req,
    output reg  [31:0] chain_k,
    input  wire [7:0]  chain_data,
    input  wire        chain_valid,
    input  wire        chain_end,
    input  wire        chain_error,
    input  wire        rd_clk,
    input  wire        rd_rst_n,
    input  wire        sample_tick,
    output reg  signed [15:0] sample_out,
    output reg         sample_valid,
    input  wire        sample_ready,
    output reg  [31:0] sample_counter,
    output wire        stream_active,
    output wire        stream_end,
    output wire        buffer_low
);

    localparam PTR_WIDTH = ADDR_WIDTH + 1;
    localparam W_IDLE = 3'd0;
    localparam W_FLUSH = 3'd1;
    localparam W_REQ = 3'd2;
    localparam W_FILL = 3'd3;
    localparam W_WAIT = 3'd4;
    localparam W_DRAIN = 3'd5;

    localparam R_IDLE = 2'd0;
    localparam R_GUARD = 2'd1;
    localparam R_PREFILL = 2'd2;
    localparam R_PLAY = 2'd3;

    reg [15:0] buffer [0:(1<<ADDR_WIDTH)-1];
    reg buf_we;
    reg [ADDR_WIDTH-1:0] buf_wa;
    reg [15:0] buf_wd;
    reg [15:0] buf_dout;

    reg [PTR_WIDTH-1:0] wr_ptr;
    reg [PTR_WIDTH-1:0] rd_ptr;
    reg [PTR_WIDTH-1:0] wr_gray;
    reg [PTR_WIDTH-1:0] rd_gray;
    reg [PTR_WIDTH-1:0] wr_gray_sync1, wr_gray_sync2;
    reg [PTR_WIDTH-1:0] rd_gray_sync1, rd_gray_sync2;

    reg [2:0] wstate;
    reg [1:0] rstate;
    reg [31:0] file_size_latched;
    reg [31:0] total_samples_latched;
    reg [31:0] total_sectors_latched;
    reg [31:0] bytes_received;
    reg [31:0] cur_k;
    reg [7:0] lo_byte;
    reg lo_pending;

    reg flush_req_toggle;
    reg flush_is_start;
    reg flush_ack_toggle;
    reg flush_req_sync1, flush_req_sync2, flush_req_seen;
    reg flush_ack_sync1, flush_ack_sync2, flush_ack_seen;
    reg finish_toggle;
    reg finish_sync1, finish_sync2, finish_seen;
    reg source_done_sync1, source_done_sync2;
    reg [6:0] guard_count;
    reg [31:0] total_samples_rd;

    function [PTR_WIDTH-1:0] to_gray;
        input [PTR_WIDTH-1:0] value;
        begin
            to_gray = value ^ (value >> 1);
        end
    endfunction

    function [PTR_WIDTH-1:0] from_gray;
        input [PTR_WIDTH-1:0] value;
        reg [PTR_WIDTH-1:0] result;
        integer i;
        begin
            result[PTR_WIDTH-1] = value[PTR_WIDTH-1];
            for (i = PTR_WIDTH-2; i >= 0; i = i-1)
                result[i] = result[i+1] ^ value[i];
            from_gray = result;
        end
    endfunction

    wire [PTR_WIDTH-1:0] wr_ptr_in_rd = from_gray(wr_gray_sync2);
    wire [PTR_WIDTH-1:0] rd_ptr_in_wr = from_gray(rd_gray_sync2);
    wire [PTR_WIDTH-1:0] level_wr = wr_ptr - rd_ptr_in_wr;
    wire [PTR_WIDTH-1:0] level_rd = wr_ptr_in_rd - rd_ptr;
    wire [31:0] next_bytes_received = bytes_received + 32'd1;
    wire byte_in_range = bytes_received < file_size_latched;

    assign stream_active = play_busy;
    assign bytes_consumed = bytes_received;
    assign stream_end = play_finish;
    assign buffer_low = (level_rd < (1 << (ADDR_WIDTH-2)));

    always @(posedge wr_clk) begin
        if (buf_we)
            buffer[buf_wa] <= buf_wd;
    end

    always @(posedge rd_clk) begin
        buf_dout <= buffer[rd_ptr[ADDR_WIDTH-1:0]];
    end

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wstate <= W_IDLE;
            play_busy <= 1'b0;
            source_done <= 1'b0;
            play_finish <= 1'b0;
            play_error <= 1'b0;
            chain_req <= 1'b0;
            chain_k <= 32'd0;
            file_size_latched <= 32'd0;
            total_samples_latched <= 32'd0;
            total_sectors_latched <= 32'd0;
            bytes_received <= 32'd0;
            cur_k <= 32'd0;
            lo_byte <= 8'd0;
            lo_pending <= 1'b0;
            wr_ptr <= {PTR_WIDTH{1'b0}};
            wr_gray <= {PTR_WIDTH{1'b0}};
            rd_gray_sync1 <= {PTR_WIDTH{1'b0}};
            rd_gray_sync2 <= {PTR_WIDTH{1'b0}};
            buf_we <= 1'b0;
            buf_wa <= {ADDR_WIDTH{1'b0}};
            buf_wd <= 16'd0;
            flush_req_toggle <= 1'b0;
            flush_is_start <= 1'b0;
            flush_ack_sync1 <= 1'b0;
            flush_ack_sync2 <= 1'b0;
            flush_ack_seen <= 1'b0;
            finish_sync1 <= 1'b0;
            finish_sync2 <= 1'b0;
            finish_seen <= 1'b0;
        end else begin
            wr_gray <= to_gray(wr_ptr);
            rd_gray_sync1 <= rd_gray;
            rd_gray_sync2 <= rd_gray_sync1;
            flush_ack_sync1 <= flush_ack_toggle;
            flush_ack_sync2 <= flush_ack_sync1;
            finish_sync1 <= finish_toggle;
            finish_sync2 <= finish_sync1;
            play_finish <= 1'b0;
            play_error <= 1'b0;
            buf_we <= 1'b0;

            if (finish_sync2 != finish_seen) begin
                finish_seen <= finish_sync2;
                play_finish <= 1'b1;
                play_busy <= 1'b0;
                source_done <= 1'b0;
                wstate <= W_IDLE;
            end

            if (play_stop && play_busy && wstate != W_FLUSH) begin
                chain_req <= 1'b0;
                flush_is_start <= 1'b0;
                flush_req_toggle <= ~flush_req_toggle;
                flush_ack_seen <= flush_ack_sync2;
                wstate <= W_FLUSH;
            end else if (play_start && !play_busy && file_size_bytes != 0 && !file_size_bytes[0]) begin
                file_size_latched <= file_size_bytes;
                total_samples_latched <= (file_size_bytes - {start_sector[22:0], 9'd0}) >> 1;
                total_sectors_latched <= (file_size_bytes + 32'd511) >> 9;
                bytes_received <= {start_sector[22:0], 9'd0};
                cur_k <= start_sector;
                lo_pending <= 1'b0;
                wr_ptr <= {PTR_WIDTH{1'b0}};
                source_done <= 1'b0;
                play_busy <= 1'b1;
                chain_req <= 1'b0;
                flush_is_start <= 1'b1;
                flush_req_toggle <= ~flush_req_toggle;
                flush_ack_seen <= flush_ack_sync2;
                wstate <= W_FLUSH;
            end else if (play_start && !play_busy) begin
                play_error <= 1'b1;
            end

            case (wstate)
                W_IDLE: chain_req <= 1'b0;
                W_FLUSH: begin
                    chain_req <= 1'b0;
                    if (flush_ack_sync2 != flush_ack_seen) begin
                        flush_ack_seen <= flush_ack_sync2;
                        if (flush_is_start)
                            wstate <= W_REQ;
                        else begin
                            play_busy <= 1'b0;
                            source_done <= 1'b0;
                            wstate <= W_IDLE;
                        end
                    end
                end
                W_REQ: begin
                    chain_req <= 1'b1;
                    chain_k <= cur_k;
                    wstate <= W_FILL;
                end
                W_FILL: begin
                    chain_req <= 1'b1;
                    chain_k <= cur_k;
                    if (chain_valid && byte_in_range) begin
                        bytes_received <= next_bytes_received;
                        if (!lo_pending) begin
                            lo_byte <= chain_data;
                            lo_pending <= 1'b1;
                        end else begin
                            buf_we <= 1'b1;
                            buf_wa <= wr_ptr[ADDR_WIDTH-1:0];
                            buf_wd <= {chain_data,lo_byte};
                            wr_ptr <= wr_ptr + 1'b1;
                            lo_pending <= 1'b0;
                        end
                    end
                    if (chain_error) begin
                        chain_req <= 1'b0;
                        play_error <= 1'b1;
                        flush_is_start <= 1'b0;
                        flush_req_toggle <= ~flush_req_toggle;
                        flush_ack_seen <= flush_ack_sync2;
                        wstate <= W_FLUSH;
                    end else if (chain_end) begin
                        chain_req <= 1'b0;
                        if ((cur_k + 1'b1) >= total_sectors_latched) begin
                            source_done <= 1'b1;
                            wstate <= W_DRAIN;
                        end else begin
                            cur_k <= cur_k + 1'b1;
                            wstate <= W_WAIT;
                        end
                    end
                end
                W_WAIT: begin
                    chain_req <= 1'b0;
                    if (level_wr <= ((1<<ADDR_WIDTH) - SAMPLES_PER_SECTOR))
                        wstate <= W_REQ;
                end
                default: chain_req <= 1'b0;
            endcase
        end
    end

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rstate <= R_IDLE;
            rd_ptr <= {PTR_WIDTH{1'b0}};
            rd_gray <= {PTR_WIDTH{1'b0}};
            wr_gray_sync1 <= {PTR_WIDTH{1'b0}};
            wr_gray_sync2 <= {PTR_WIDTH{1'b0}};
            flush_req_sync1 <= 1'b0;
            flush_req_sync2 <= 1'b0;
            flush_req_seen <= 1'b0;
            flush_ack_toggle <= 1'b0;
            finish_toggle <= 1'b0;
            source_done_sync1 <= 1'b0;
            source_done_sync2 <= 1'b0;
            total_samples_rd <= 32'd0;
            guard_count <= 7'd0;
            sample_out <= 16'sd0;
            sample_valid <= 1'b0;
            sample_counter <= 32'd0;
        end else begin
            rd_gray <= to_gray(rd_ptr);
            wr_gray_sync1 <= wr_gray;
            wr_gray_sync2 <= wr_gray_sync1;
            flush_req_sync1 <= flush_req_toggle;
            flush_req_sync2 <= flush_req_sync1;
            source_done_sync1 <= source_done;
            source_done_sync2 <= source_done_sync1;
            sample_valid <= 1'b0;

            if (flush_req_sync2 != flush_req_seen) begin
                flush_req_seen <= flush_req_sync2;
                rd_ptr <= {PTR_WIDTH{1'b0}};
                rd_gray <= {PTR_WIDTH{1'b0}};
                sample_counter <= 32'd0;
                sample_out <= 16'sd0;
                total_samples_rd <= total_samples_latched;
                guard_count <= 7'd0;
                if (flush_is_start)
                    rstate <= R_GUARD;
                else
                    rstate <= R_IDLE;
                flush_ack_toggle <= ~flush_ack_toggle;
            end else if (sample_tick && sample_ready) begin
                sample_valid <= 1'b1;
                case (rstate)
                    R_IDLE: sample_out <= 16'sd0;
                    R_GUARD: begin
                        sample_out <= 16'sd0;
                        if (guard_count >= GUARD_SAMPLES-1)
                            rstate <= R_PREFILL;
                        else
                            guard_count <= guard_count + 1'b1;
                    end
                    R_PREFILL: begin
                        sample_out <= 16'sd0;
                        if ((level_rd >= SAMPLES_PER_SECTOR) ||
                            (source_done_sync2 && level_rd != 0))
                            rstate <= R_PLAY;
                    end
                    default: begin
                        if (sample_counter >= total_samples_rd) begin
                            sample_out <= 16'sd0;
                            rstate <= R_IDLE;
                        end else if (level_rd != 0) begin
                            sample_out <= buf_dout;
                            rd_ptr <= rd_ptr + 1'b1;
                            sample_counter <= sample_counter + 1'b1;
                            if (source_done_sync2 && (sample_counter + 1'b1 >= total_samples_rd)) begin
                                finish_toggle <= ~finish_toggle;
                                rstate <= R_IDLE;
                            end
                        end else begin
                            sample_out <= 16'sd0;
                        end
                    end
                endcase
            end
        end
    end
endmodule
