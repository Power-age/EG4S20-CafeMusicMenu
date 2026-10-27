`timescale 1ns/1ps

module mask_slide #(
    parameter integer STEP  = 7,
    parameter integer START = 200,
    parameter integer MINWAIT = 8
)(
    input             clk,
    input             rst,
    input             page_changed,
    input             trans_active,
    input             frame_tick,
    output reg [9:0]  slide
);
    localparam [9:0] SLIDE_START = START;
    localparam [9:0] SLIDE_STEP  = STEP;

    reg run;
    reg pend;
    reg [3:0] hold;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            slide <= SLIDE_START;
            run   <= 1'b1;
            pend  <= 1'b0;
            hold  <= 4'd0;
        end
        else if (page_changed) begin
            slide <= SLIDE_START;
            run   <= 1'b0;
            pend  <= 1'b1;
            hold  <= MINWAIT[3:0];
        end
        else if (pend) begin
            if (hold != 4'd0) begin
                if (frame_tick) hold <= hold - 4'd1;
            end
            else if (!trans_active) begin
                pend <= 1'b0;
                run  <= 1'b1;
            end
        end
        else if (run && frame_tick) begin
            if (slide <= SLIDE_STEP) begin
                slide <= 10'd0;
                run   <= 1'b0;
            end
            else begin
                slide <= slide - SLIDE_STEP;
            end
        end
    end
endmodule
