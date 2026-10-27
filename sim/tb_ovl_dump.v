`timescale 1ns/1ps
module tb_ovl_dump;
    reg clk = 1'b0, rst = 1'b1;
    reg I_de = 1'b0, I_vs = 1'b0;
    reg [9:0] x = 10'd0, y = 10'd0;
    reg [23:0] I_rgb = 24'h808080;
    reg [1:0] I_ui_alpha = 2'd3;
    reg I_panel_vis = 1'b0;
    reg [2:0] I_bar_vol = 3'd0, I_bar_bri = 3'd0, I_bar_con = 3'd0;
    wire [10:0] rd_x;
    wire [6:0] rd_y;
    wire rd_en;
    wire [23:0] O_rgb;
    wire O_de, O_vs;

    reg [1:0] rd_data;
    integer row, col, fd;

    osd_buffer_overlay u_dut (
        .I_clk(clk), .I_rst(rst), .I_de(I_de), .I_vs(I_vs), .I_rgb(I_rgb),
        .I_ui_alpha(I_ui_alpha), .I_panel_vis(I_panel_vis),
        .I_bar_vol(I_bar_vol), .I_bar_bri(I_bar_bri), .I_bar_con(I_bar_con),
        .rd_x(rd_x), .rd_y(rd_y), .rd_en(rd_en), .rd_data(rd_data),
        .O_rgb(O_rgb), .O_de(O_de), .O_vs(O_vs)
    );

    always #19.861 clk = ~clk;

    reg [1:0] rd_data_q;
    always @(posedge clk) begin
        if (rd_en && rd_y >= 7'd60 && rd_y <= 7'd66 && rd_x >= 7'd48)
            rd_data_q <= 2'b10;
        else
            rd_data_q <= 2'b00;
    end
    always @(*) rd_data = rd_data_q;

    initial begin
        fd = $fopen("ovl_dump.txt", "w");
        repeat (4) @(posedge clk);
        rst <= 1'b0;
        repeat (2) @(posedge clk);
        for (row = 0; row < 480; row = row + 1) begin
            for (col = 0; col < 640; col = col + 1) begin
                @(negedge clk);
                x <= col[9:0]; y <= row[9:0]; I_de <= 1'b1;
                @(negedge clk);
                @(negedge clk);
                $fwrite(fd, "%0d %0d %06h\n", x, y, O_rgb);
            end
        end
        $fclose(fd);
        $display("DUMP_DONE");
        $finish;
    end
endmodule


