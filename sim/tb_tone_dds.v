`timescale 1ns/1ps

module tb_tone_dds;
    reg clk = 0, rst = 1;
    wire valid;
    wire [23:0] sample;
    integer ticks = 0;
    integer clks = 0;

    always #20 clk = ~clk;

    tone_dds dut (.clk(clk), .rst(rst), .o_valid(valid), .o_sample(sample));

    always @(posedge clk) begin
        clks = clks + 1;
        if (valid) ticks = ticks + 1;
    end

    initial begin
        rst = 1;
        #200 rst = 0;
        #(40 * 1000000);
        $display("clks=%0d ticks=%0d expect=%0d", clks, ticks, (clks * 48) / 25000);
        if ((ticks > ((clks * 48) / 25000) - 4) && (ticks < ((clks * 48) / 25000) + 4))
            $display("PASS tb_tone_dds");
        else
            $display("FAIL tb_tone_dds");
        $finish;
    end
endmodule
