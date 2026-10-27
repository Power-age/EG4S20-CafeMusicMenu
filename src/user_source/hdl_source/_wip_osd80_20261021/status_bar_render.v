module status_bar_render #(
    parameter [5:0] P_FRAMES_PER_SEC = 6'd59,
    parameter [5:0] P_SEC_MAX        = 6'd59,
    parameter [5:0] P_MIN_MAX        = 6'd59,
    parameter [6:0] P_HOUR_MAX       = 7'd99
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        vs,
    input  wire [87:0] track_name,
    input  wire [3:0]  vol_level,
    input  wire [1:0]  img_idx,
    input  wire        auto_en,
    output reg         req_valid,
    output wire [6:0]  req_ascii,
    output wire [7:0]  req_x,
    output wire [6:0]  req_y,
    output wire [1:0]  req_type,
    input  wire        req_ready
);

    localparam [5:0] COL_MAX = 6'd31;

    reg       vs_d;
    reg [5:0] frame_cnt;
    reg [6:0] hour;
    reg [5:0] minute;
    reg [5:0] second;

    wire vs_rise = vs & ~vs_d;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            vs_d      <= 1'b0;
            frame_cnt <= 6'd0;
            hour      <= 7'd0;
            minute    <= 6'd0;
            second    <= 6'd0;
        end else begin
            vs_d <= vs;
            if (vs_rise) begin
                if (frame_cnt == P_FRAMES_PER_SEC) begin
                    frame_cnt <= 6'd0;
                    if (second == P_SEC_MAX) begin
                        second <= 6'd0;
                        if (minute == P_MIN_MAX) begin
                            minute <= 6'd0;
                            if (hour == P_HOUR_MAX)
                                hour <= 7'd0;
                            else
                                hour <= hour + 7'd1;
                        end else begin
                            minute <= minute + 6'd1;
                        end
                    end else begin
                        second <= second + 6'd1;
                    end
                end else begin
                    frame_cnt <= frame_cnt + 6'd1;
                end
            end
        end
    end

    reg [87:0] snap_name;
    reg [3:0]  snap_vol;
    reg [1:0]  snap_img;
    reg        snap_auto;
    reg [6:0]  snap_hour;
    reg [5:0]  snap_min;
    reg [5:0]  snap_sec;
    reg        booted;
    reg        sending;
    reg [5:0]  col;

    wire need_refresh =
          ~booted
        | (track_name != snap_name)
        | (vol_level  != snap_vol)
        | (img_idx    != snap_img)
        | (auto_en    != snap_auto)
        | (hour       != snap_hour)
        | (minute     != snap_min)
        | (second     != snap_sec);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            booted    <= 1'b0;
            sending   <= 1'b0;
            req_valid <= 1'b0;
            col       <= 6'd0;
            snap_name <= 88'd0;
            snap_vol  <= 4'd0;
            snap_img  <= 2'd0;
            snap_auto <= 1'b0;
            snap_hour <= 7'd0;
            snap_min  <= 6'd0;
            snap_sec  <= 6'd0;
        end else if (!sending) begin
            if (need_refresh) begin
                sending   <= 1'b1;
                req_valid <= 1'b1;
                col       <= 6'd0;
                snap_name <= track_name;
                snap_vol  <= vol_level;
                snap_img  <= img_idx;
                snap_auto <= auto_en;
                snap_hour <= hour;
                snap_min  <= minute;
                snap_sec  <= second;
            end
        end else if (req_ready) begin
            if (col == COL_MAX) begin
                sending   <= 1'b0;
                req_valid <= 1'b0;
                col       <= 6'd0;
                booted    <= 1'b1;
            end else begin
                col <= col + 6'd1;
            end
        end
    end

    function [3:0] bcd_tens;
        input [6:0] v;
        begin
            if (v >= 7'd90)
                bcd_tens = 4'd9;
            else if (v >= 7'd80)
                bcd_tens = 4'd8;
            else if (v >= 7'd70)
                bcd_tens = 4'd7;
            else if (v >= 7'd60)
                bcd_tens = 4'd6;
            else if (v >= 7'd50)
                bcd_tens = 4'd5;
            else if (v >= 7'd40)
                bcd_tens = 4'd4;
            else if (v >= 7'd30)
                bcd_tens = 4'd3;
            else if (v >= 7'd20)
                bcd_tens = 4'd2;
            else if (v >= 7'd10)
                bcd_tens = 4'd1;
            else
                bcd_tens = 4'd0;
        end
    endfunction

    function [3:0] bcd_ones;
        input [6:0] v;
        input [3:0] t;
        begin
            bcd_ones = v - {t, 3'd0} - {t, 1'd0};
        end
    endfunction

    wire [3:0] hh_t = bcd_tens(snap_hour);
    wire [3:0] hh_o = bcd_ones(snap_hour, hh_t);
    wire [3:0] mm_t = bcd_tens({1'b0, snap_min});
    wire [3:0] mm_o = bcd_ones({1'b0, snap_min}, mm_t);
    wire [3:0] ss_t = bcd_tens({1'b0, snap_sec});
    wire [3:0] ss_o = bcd_ones({1'b0, snap_sec}, ss_t);

    wire [3:0] vol_t = (snap_vol >= 4'd10) ? 4'd1 : 4'd0;
    wire [3:0] vol_o = snap_vol - (vol_t[0] ? 4'd10 : 4'd0);

    wire [7:0] nm0 = snap_name[87:80];
    wire [7:0] nm1 = snap_name[79:72];
    wire [7:0] nm2 = snap_name[71:64];
    wire [7:0] nm3 = snap_name[63:56];
    wire [7:0] nm4 = snap_name[55:48];
    wire [7:0] nm5 = snap_name[47:40];
    wire [7:0] nm6 = snap_name[39:32];
    wire [7:0] nm7 = snap_name[31:24];

    reg [6:0] char;
    always @(*) begin
        case (col)
            6'd0:  char = nm0[6:0];
            6'd1:  char = nm1[6:0];
            6'd2:  char = nm2[6:0];
            6'd3:  char = nm3[6:0];
            6'd4:  char = nm4[6:0];
            6'd5:  char = nm5[6:0];
            6'd6:  char = nm6[6:0];
            6'd7:  char = nm7[6:0];
            6'd8:  char = 7'd86;
            6'd9:  char = 7'd48 + {3'd0, vol_t};
            6'd10: char = 7'd48 + {3'd0, vol_o};
            6'd11: char = 7'd32;
            6'd12: char = 7'd48 + {3'd0, hh_t};
            6'd13: char = 7'd48 + {3'd0, hh_o};
            6'd14: char = 7'd58;
            6'd15: char = 7'd48 + {3'd0, mm_t};
            6'd16: char = 7'd48 + {3'd0, mm_o};
            6'd17: char = 7'd58;
            6'd18: char = 7'd48 + {3'd0, ss_t};
            6'd19: char = 7'd48 + {3'd0, ss_o};
            6'd20: char = 7'd32;
            6'd21: char = 7'd80;
            6'd22: char = 7'd73;
            6'd23: char = 7'd67;
            6'd24: char = 7'd49 + {5'd0, snap_img};
            6'd25: char = 7'd47;
            6'd26: char = 7'd52;
            6'd27: char = 7'd32;
            6'd28: char = snap_auto ? 7'd65 : 7'd77;
            6'd29: char = snap_auto ? 7'd85 : 7'd65;
            6'd30: char = snap_auto ? 7'd84 : 7'd78;
            6'd31: char = snap_auto ? 7'd79 : 7'd32;
            default: char = 7'd32;
        endcase
    end

    assign req_ascii = char;
    assign req_x     = {2'd0, col};
    assign req_y     = 7'd72;
    assign req_type  = 2'b10;

endmodule
