module ui_visible_ctl #(
    parameter [9:0] P_HOLD_FRAMES    = 10'd300,
    parameter [1:0] P_FADE_STEP_FRAMES = 2'd3
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        vs,
    input  wire [87:0] track_name,
    input  wire [3:0]  vol_level,
    input  wire [1:0]  img_idx,
    input  wire        auto_en,
    input  wire [1:0]  brightness_level,
    input  wire [1:0]  contrast_level,
    input  wire [3:0]  state_code,
    output reg  [2:0]  ui_alpha
);

    localparam [1:0] S_SHOW     = 2'd0;
    localparam [1:0] S_FADE_OUT = 2'd1;
    localparam [1:0] S_HIDDEN   = 2'd2;

    reg        vs_d;
    reg [1:0]  fsm;
    reg [9:0]  hold_cnt;
    reg [1:0]  step_cnt;

    reg [3:0]  state_meta;
    reg [3:0]  state_sync;

    reg [87:0] name_d;
    reg [3:0]  vol_d;
    reg [1:0]  img_d;
    reg        auto_d;
    reg [1:0]  bri_d;
    reg [1:0]  con_d;
    reg [3:0]  st_d;

    wire vs_rise = vs & ~vs_d;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state_meta <= 4'd0;
            state_sync <= 4'd0;
        end else begin
            state_meta <= state_code;
            state_sync <= state_meta;
        end
    end

    wire event_now = (track_name      != name_d)
                   | (vol_level       != vol_d)
                   | (img_idx         != img_d)
                   | (auto_en         != auto_d)
                   | (brightness_level != bri_d)
                   | (contrast_level   != con_d)
                   | (state_sync      != st_d);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            vs_d      <= 1'b0;
            fsm       <= S_SHOW;
            hold_cnt  <= 10'd0;
            step_cnt  <= 2'd0;
            ui_alpha  <= 3'd7;
            name_d    <= 88'd0;
            vol_d     <= 4'd0;
            img_d     <= 2'd0;
            auto_d    <= 1'b0;
            bri_d     <= 2'd0;
            con_d     <= 2'd0;
            st_d      <= 4'd0;
        end else begin
            vs_d <= vs;
            if (vs_rise) begin
                name_d <= track_name;
                vol_d  <= vol_level;
                img_d  <= img_idx;
                auto_d <= auto_en;
                bri_d  <= brightness_level;
                con_d  <= contrast_level;
                st_d   <= state_sync;

                case (fsm)
                    S_SHOW: begin
                        ui_alpha <= 3'd7;
                        if (event_now) begin
                            hold_cnt <= 10'd0;
                        end else if (hold_cnt == P_HOLD_FRAMES) begin
                            fsm       <= S_FADE_OUT;
                            step_cnt  <= 2'd0;
                            ui_alpha  <= 3'd6;
                        end else begin
                            hold_cnt <= hold_cnt + 10'd1;
                        end
                    end
                    S_FADE_OUT: begin
                        if (event_now) begin
                            fsm      <= S_SHOW;
                            ui_alpha <= 3'd7;
                            hold_cnt <= 10'd0;
                        end else if (step_cnt == P_FADE_STEP_FRAMES) begin
                            step_cnt <= 2'd0;
                            if (ui_alpha == 3'd0) begin
                                fsm <= S_HIDDEN;
                            end else begin
                                ui_alpha <= ui_alpha - 3'd1;
                            end
                        end else begin
                            step_cnt <= step_cnt + 2'd1;
                        end
                    end
                    default: begin
                        ui_alpha <= 3'd0;
                        if (event_now) begin
                            fsm      <= S_SHOW;
                            ui_alpha <= 3'd7;
                            hold_cnt <= 10'd0;
                        end
                    end
                endcase
            end
        end
    end

endmodule
