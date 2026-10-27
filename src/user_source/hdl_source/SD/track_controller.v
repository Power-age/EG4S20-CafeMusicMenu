module track_controller (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    input  wire [15:0] valid_mask,
    input  wire [4:0]  track_count,
    input  wire        cmd_prev,
    input  wire        cmd_next,
    input  wire        seek_req,
    input  wire        seek_fwd,
    input  wire [31:0] bytes_consumed,
    output reg  [31:0] player_start_sector,
    output reg         lookup_req,
    output reg  [3:0]  lookup_index,
    input  wire        lookup_valid,
    input  wire [87:0] lookup_name,
    input  wire [31:0] lookup_cluster,
    input  wire [31:0] lookup_size,
    input  wire        player_busy,
    input  wire        player_finish,
    input  wire        player_error,
    output reg         player_start,
    output reg         player_stop,
    output reg  [31:0] player_size,
    input  wire        sector_idle,
    output reg         chain_load_start,
    output reg  [31:0] chain_start_cluster,
    output reg         playlist_active,
    output reg  [3:0]  current_index,
    output reg  [87:0] current_name
);

    localparam C_EMPTY = 4'd0;
    localparam C_SELECT = 4'd1;
    localparam C_LOOKUP_REQ = 4'd2;
    localparam C_LOOKUP_WAIT = 4'd3;
    localparam C_STOP = 4'd4;
    localparam C_WAIT_STOP = 4'd5;
    localparam C_WAIT_SECTOR = 4'd6;
    localparam C_CHAIN_LOAD = 4'd7;
    localparam C_SETTLE = 4'd8;
    localparam C_START = 4'd9;
    localparam C_RUN = 4'd10;

    reg [3:0] state;
    reg [15:0] failed_mask;
    reg [3:0] target_index;
    reg [1:0] select_reason;
    reg [87:0] selected_name;
    reg [31:0] selected_cluster;
    reg [31:0] selected_size;
    reg reselect_after_stop;
    reg [31:0] seek_sector;

    wire [31:0] cur_sector  = bytes_consumed >> 9;
    wire [31:0] fwd_sector  = cur_sector + 32'd1875;
    wire [31:0] bwd_sector  = (cur_sector > 32'd1875) ? (cur_sector - 32'd1875) : 32'd0;
    wire [31:0] total_sect  = (selected_size + 32'd511) >> 9;

    function [3:0] next_valid;
        input [3:0] current;
        input [15:0] mask;
        begin
            if      (mask[current + 4'd1])  next_valid = current + 4'd1;
            else if (mask[current + 4'd2])  next_valid = current + 4'd2;
            else if (mask[current + 4'd3])  next_valid = current + 4'd3;
            else if (mask[current + 4'd4])  next_valid = current + 4'd4;
            else if (mask[current + 4'd5])  next_valid = current + 4'd5;
            else if (mask[current + 4'd6])  next_valid = current + 4'd6;
            else if (mask[current + 4'd7])  next_valid = current + 4'd7;
            else if (mask[current + 4'd8])  next_valid = current + 4'd8;
            else if (mask[current + 4'd9])  next_valid = current + 4'd9;
            else if (mask[current + 4'd10]) next_valid = current + 4'd10;
            else if (mask[current + 4'd11]) next_valid = current + 4'd11;
            else if (mask[current + 4'd12]) next_valid = current + 4'd12;
            else if (mask[current + 4'd13]) next_valid = current + 4'd13;
            else if (mask[current + 4'd14]) next_valid = current + 4'd14;
            else if (mask[current + 4'd15]) next_valid = current + 4'd15;
            else                           next_valid = current;
        end
    endfunction

    function [3:0] prev_valid;
        input [3:0] current;
        input [15:0] mask;
        begin
            if      (mask[current - 4'd1])  prev_valid = current - 4'd1;
            else if (mask[current - 4'd2])  prev_valid = current - 4'd2;
            else if (mask[current - 4'd3])  prev_valid = current - 4'd3;
            else if (mask[current - 4'd4])  prev_valid = current - 4'd4;
            else if (mask[current - 4'd5])  prev_valid = current - 4'd5;
            else if (mask[current - 4'd6])  prev_valid = current - 4'd6;
            else if (mask[current - 4'd7])  prev_valid = current - 4'd7;
            else if (mask[current - 4'd8])  prev_valid = current - 4'd8;
            else if (mask[current - 4'd9])  prev_valid = current - 4'd9;
            else if (mask[current - 4'd10]) prev_valid = current - 4'd10;
            else if (mask[current - 4'd11]) prev_valid = current - 4'd11;
            else if (mask[current - 4'd12]) prev_valid = current - 4'd12;
            else if (mask[current - 4'd13]) prev_valid = current - 4'd13;
            else if (mask[current - 4'd14]) prev_valid = current - 4'd14;
            else if (mask[current - 4'd15]) prev_valid = current - 4'd15;
            else                           prev_valid = current;
        end
    endfunction

    function [3:0] first_valid;
        input [15:0] mask;
        begin
            if      (mask[0])  first_valid = 4'd0;
            else if (mask[1])  first_valid = 4'd1;
            else if (mask[2])  first_valid = 4'd2;
            else if (mask[3])  first_valid = 4'd3;
            else if (mask[4])  first_valid = 4'd4;
            else if (mask[5])  first_valid = 4'd5;
            else if (mask[6])  first_valid = 4'd6;
            else if (mask[7])  first_valid = 4'd7;
            else if (mask[8])  first_valid = 4'd8;
            else if (mask[9])  first_valid = 4'd9;
            else if (mask[10]) first_valid = 4'd10;
            else if (mask[11]) first_valid = 4'd11;
            else if (mask[12]) first_valid = 4'd12;
            else if (mask[13]) first_valid = 4'd13;
            else if (mask[14]) first_valid = 4'd14;
            else if (mask[15]) first_valid = 4'd15;
            else               first_valid = 4'd0;
        end
    endfunction

    wire [15:0] available_mask = valid_mask & ~failed_mask;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= C_EMPTY;
            failed_mask <= 16'd0;
            target_index <= 4'd0;
            select_reason <= 2'd0;
            lookup_req <= 1'b0;
            lookup_index <= 4'd0;
            player_start <= 1'b0;
            player_stop <= 1'b0;
            player_size <= 32'd0;
            chain_load_start <= 1'b0;
            chain_start_cluster <= 32'd0;
            playlist_active <= 1'b0;
            current_index <= 4'd0;
            current_name <= 88'd0;
            selected_name <= 88'd0;
            selected_cluster <= 32'd0;
            selected_size <= 32'd0;
            reselect_after_stop <= 1'b0;
            seek_sector <= 32'd0;
            player_start_sector <= 32'd0;
        end else begin
            lookup_req <= 1'b0;
            player_start <= 1'b0;
            player_stop <= 1'b0;
            chain_load_start <= 1'b0;
            if (!enable) begin
                state <= C_EMPTY;
                failed_mask <= 16'd0;
                playlist_active <= 1'b0;
            end else begin
                case (state)
                    C_EMPTY: begin
                        playlist_active <= 1'b0;
                        if (track_count != 0 && valid_mask != 0) begin
                            target_index <= first_valid(valid_mask);
                            select_reason <= 2'd0;
                            state <= C_LOOKUP_REQ;
                        end
                    end
                    C_SELECT: begin
                        if (available_mask == 0) begin
                            playlist_active <= 1'b0;
                            state <= C_EMPTY;
                        end else begin
                            case (select_reason)
                                2'd2: target_index <= prev_valid(current_index,available_mask);
                                default: target_index <= next_valid(current_index,available_mask);
                            endcase
                            state <= C_LOOKUP_REQ;
                        end
                    end
                    C_LOOKUP_REQ: begin
                        lookup_req <= 1'b1;
                        lookup_index <= target_index;
                        state <= C_LOOKUP_WAIT;
                    end
                    C_LOOKUP_WAIT: begin
                        if (lookup_valid) begin
                            selected_name <= lookup_name;
                            selected_cluster <= lookup_cluster;
                            selected_size <= lookup_size;
                            if (player_busy)
                                state <= C_STOP;
                            else
                                state <= C_WAIT_SECTOR;
                        end
                    end
                    C_STOP: begin
                        player_stop <= 1'b1;
                        state <= C_WAIT_STOP;
                    end
                    C_WAIT_STOP: begin
                        if (!player_busy) begin
                            if (reselect_after_stop) begin
                                reselect_after_stop <= 1'b0;
                                state <= C_SELECT;
                            end else begin
                                state <= C_WAIT_SECTOR;
                            end
                        end
                    end
                    C_WAIT_SECTOR: begin
                        if (sector_idle)
                            state <= C_CHAIN_LOAD;
                    end
                    C_CHAIN_LOAD: begin
                        chain_load_start <= 1'b1;
                        chain_start_cluster <= selected_cluster;
                        player_start_sector <= seek_sector;
                        state <= C_SETTLE;
                    end
                    C_SETTLE: state <= C_START;
                    C_START: begin
                        player_size <= selected_size;
                        player_start <= 1'b1;
                        current_index <= target_index;
                        current_name <= selected_name;
                        playlist_active <= 1'b1;
                        state <= C_RUN;
                    end
                    default: begin
                        if (player_error) begin
                            failed_mask[current_index] <= 1'b1;
                            select_reason <= 2'd1;
                            reselect_after_stop <= 1'b1;
                            seek_sector <= 32'd0;
                            state <= C_STOP;
                        end else if (seek_req) begin
                            if (seek_fwd && (fwd_sector >= total_sect)) begin
                                select_reason <= 2'd1;
                                seek_sector <= 32'd0;
                                state <= C_SELECT;
                            end else begin
                                seek_sector <= seek_fwd ? fwd_sector : bwd_sector;
                                state <= C_STOP;
                            end
                        end else if (cmd_next) begin
                            select_reason <= 2'd1;
                            seek_sector <= 32'd0;
                            state <= C_SELECT;
                        end else if (cmd_prev) begin
                            select_reason <= 2'd2;
                            seek_sector <= 32'd0;
                            state <= C_SELECT;
                        end else if (player_finish) begin
                            select_reason <= 2'd1;
                            seek_sector <= 32'd0;
                            state <= C_SELECT;
                        end
                    end
                endcase
            end
        end
    end
endmodule
