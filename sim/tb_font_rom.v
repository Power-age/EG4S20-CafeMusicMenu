`timescale 1ns/1ps
module tb_font_rom;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1;
    reg rd_en = 1'b0;
    reg [6:0] ascii = 7'd0;
    reg [2:0] row = 3'd0;
    wire [7:0] rd_data;
    wire rd_valid;
    reg [7:0] reference [0:1023];
    integer code;
    integer line_no;
    integer failures = 0;
    reg [63:0] a_rows = 64'h00103838484c0000;

    font_rom dut (
        .clk(clk), .rst(rst), .rd_en(rd_en), .ascii(ascii), .row(row),
        .rd_data(rd_data), .rd_valid(rd_valid)
    );

    task check;
        input [6:0] character;
        input [2:0] line_index;
        input enable;
        reg [7:0] expected;
        begin
            @(negedge clk);
            ascii = character;
            row = line_index;
            rd_en = enable;
            expected = character >= 7'd32 ? reference[{character,line_index}] : 8'd0;
            @(posedge clk);
            #1;
            if (rd_valid !== enable || (enable && rd_data !== expected)) begin
                $display("FAIL ascii=%d row=%d expected=%h actual=%h valid=%b", character, line_index, expected, rd_data, rd_valid);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        $readmemh("font_data.mem", reference);
        repeat (2) @(negedge clk);
        rst = 1'b0;
        for (code = 0; code < 128; code = code + 1)
            for (line_no = 0; line_no < 8; line_no = line_no + 1)
                check(code, line_no, 1'b1);
        for (line_no = 0; line_no < 8; line_no = line_no + 1) begin
            if (reference[65*8+line_no] !== a_rows[63-line_no*8 -: 8]) begin
                $display("FAIL A row=%d", line_no);
                failures = failures + 1;
            end
        end
        if (reference[127*8] !== 8'h7e || reference[127*8+6] !== 8'h7e) begin
            $display("FAIL DEL pattern");
            failures = failures + 1;
        end
        check(7'd32, 3'd0, 1'b0);
        check(7'd127, 3'd7, 1'b1);
        @(negedge clk);
        rst = 1'b1;
        #1;
        if (rd_valid !== 1'b0) begin
            $display("FAIL reset valid");
            failures = failures + 1;
        end
        if (failures == 0) $display("PASS tb_font_rom");
        else $fatal(1, "tb_font_rom failures=%0d", failures);
        $finish;
    end
endmodule
