`timescale 1ns/1ps

module video_zoom (
    input             clk,
    input             rst,
    input             zoom_en,
    input      [9:0]  col0,
    input             de,
    input             vs,
    input      [31:0] fifo_data,
    output            z_pop,
    output     [23:0] z_data
);
    localparam [9:0] WIDTH = 10'd320;

    reg [20:0] de_d;
    always @(posedge clk or posedge rst) begin
        if (rst) de_d <= 21'd0;
        else     de_d <= {de_d[19:0], de};
    end
    wire de18 = de_d[18];
    wire de19 = de_d[19];

    reg [9:0] x18;
    always @(posedge clk or posedge rst) begin
        if (rst)         x18 <= 10'd0;
        else if (!de18)  x18 <= 10'd0;
        else             x18 <= x18 + 10'd1;
    end

    reg        de18_d;
    reg        vs_d;
    reg [9:0]  y18;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            de18_d <= 1'b0;
            vs_d   <= 1'b0;
            y18    <= 10'd0;
        end
        else begin
            de18_d <= de18;
            vs_d   <= vs;
            if (vs && !vs_d)            y18 <= 10'd0;
            else if (!de18 && de18_d)   y18 <= y18 + 10'd1;
        end
    end

    reg [9:0] x18_q;
    reg [9:0] y18_q;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            x18_q <= 10'd0;
            y18_q <= 10'd0;
        end
        else begin
            x18_q <= x18;
            y18_q <= y18;
        end
    end

    assign z_pop = zoom_en && de18 && ~y18[0];

    wire [9:0]  wr_row  = y18_q >> 1;
    wire        wr_en   = zoom_en && de19 && ~y18_q[0] && (x18_q >= col0) && (x18_q < (col0 + WIDTH));
    wire [8:0]  wr_col  = x18_q[8:0] - col0[8:0];
    wire [9:0]  wr_addr = (wr_row[0] ? 10'd512 : 10'd0) + {1'b0, wr_col};
    wire [23:0] wr_data = fifo_data[31:8];

    wire [9:0]  disp_row = (y18 - 10'd2) >> 1;
    wire        row_sel  = disp_row[0];
    wire        vblend   = y18[0];

    wire [9:0]  rd_a_raw = (x18 + 10'd1) >> 1;
    wire [8:0]  rd_m     = (rd_a_raw > 10'd319) ? 9'd319 : rd_a_raw[8:0];
    wire [9:0]  rd_cur   = (row_sel ? 10'd512 : 10'd0) + {1'b0, rd_m};
    wire [9:0]  rd_nxt   = (row_sel ? 10'd0 : 10'd512) + {1'b0, rd_m};

    wire [23:0] dob_cur;
    wire [23:0] dob_nxt;

    reg [23:0] prev_cur;
    reg [23:0] prev_nxt;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            prev_cur <= 24'd0;
            prev_nxt <= 24'd0;
        end
        else begin
            prev_cur <= dob_cur;
            prev_nxt <= dob_nxt;
        end
    end

    wire        px_odd = ~x18[0];

    function [23:0] avg2;
        input [23:0] a;
        input [23:0] b;
        reg [8:0] sr;
        reg [8:0] sg;
        reg [8:0] sb;
        begin
            sr = {1'b0, a[23:16]} + {1'b0, b[23:16]};
            sg = {1'b0, a[15:8]}  + {1'b0, b[15:8]};
            sb = {1'b0, a[7:0]}   + {1'b0, b[7:0]};
            avg2 = { sr[8:1], sg[8:1], sb[8:1] };
        end
    endfunction

    wire [23:0] h_cur = px_odd ? avg2(dob_cur, prev_cur) : dob_cur;
    wire [23:0] h_nxt = px_odd ? avg2(dob_nxt, prev_nxt) : dob_nxt;
    wire [23:0] mix   = vblend ? avg2(h_cur, h_nxt) : h_cur;

    assign z_data = (zoom_en && (y18 <= 10'd1)) ? 24'd0 : mix;

`ifdef ZOOM_SIM
    reg [23:0] sim_mem [0:1023];
    reg [23:0] q_b_r;
    reg [23:0] q_a_r;
    always @(posedge clk) begin
        if (wr_en) sim_mem[wr_addr] <= wr_data;
        q_b_r <= sim_mem[rd_cur];
        q_a_r <= sim_mem[rd_nxt];
    end
    assign dob_cur = q_b_r;
    assign dob_nxt = wr_en ? 24'd0 : q_a_r;
`else
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(24), .ADDR_WIDTH_A(10), .DATA_DEPTH_A(1024),
        .DATA_WIDTH_B(24), .ADDR_WIDTH_B(10), .DATA_DEPTH_B(1024),
        .MODE("DP"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("OFF"), .INIT_FILE("NONE"), .FILL_ALL("NONE"),
        .IMPLEMENT("9K")
    ) zoom_line_ram (
        .dia(wr_data), .addra(wr_en ? wr_addr : rd_nxt), .cea(1'b1), .ocea(1'b0),
        .clka(clk), .wea(wr_en), .rsta(1'b0), .bea(1'b0),
        .dib(24'd0), .addrb(rd_cur), .ceb(1'b1), .oceb(1'b0),
        .clkb(clk), .web(1'b0), .rstb(1'b0), .beb(1'b0),
        .doa(dob_nxt), .dob(dob_cur)
    );
`endif
endmodule
