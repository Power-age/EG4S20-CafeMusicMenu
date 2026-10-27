`timescale 1ns/1ps

module tone_dds (
    input             clk,
    input             rst,
    output reg        o_valid,
    output reg [23:0] o_sample
);
    localparam integer CLK_HZ = 25000000;
    localparam integer FS_HZ  = 48000;
    localparam [23:0]  AMP    = 24'sd2000000;
    localparam [15:0]  HOLD   = 16'd23999;

    reg [24:0] frac;
    reg [31:0] phase;
    reg [2:0]  note_idx;
    reg [15:0] note_cnt;

    function [31:0] note_inc;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: note_inc = 32'd25165824;
                3'd1: note_inc = 32'd29360128;
                3'd2: note_inc = 32'd33554432;
                3'd3: note_inc = 32'd37748736;
                3'd4: note_inc = 32'd41943040;
                3'd5: note_inc = 32'd46137344;
                3'd6: note_inc = 32'd50331648;
                default: note_inc = 32'd54525952;
            endcase
        end
    endfunction

    wire [24:0] frac_nxt = frac + FS_HZ;
    wire        tick     = (frac_nxt >= CLK_HZ);
    wire [31:0] phase_nxt = phase + note_inc(note_idx);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            frac     <= 25'd0;
            phase    <= 32'd0;
            note_idx <= 3'd0;
            note_cnt <= 16'd0;
            o_valid  <= 1'b0;
            o_sample <= 24'sd0;
        end
        else begin
            if (tick) begin
                frac     <= frac_nxt - CLK_HZ;
                phase    <= phase_nxt;
                o_valid  <= 1'b1;
                o_sample <= phase_nxt[31] ? AMP : -AMP;
                if (note_cnt == HOLD) begin
                    note_cnt <= 16'd0;
                    note_idx <= (note_idx == 3'd7) ? 3'd0 : (note_idx + 3'd1);
                end
                else note_cnt <= note_cnt + 16'd1;
            end
            else begin
                frac    <= frac_nxt;
                o_valid <= 1'b0;
            end
        end
    end
endmodule
