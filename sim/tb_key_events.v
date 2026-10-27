`timescale 1ns/1ps

// key_events 单元测试：双击判定、延迟单击、长按、去抖
// 参数压缩以便快速仿真（CLOCK_MHZ=1 时 1ms = 1000 拍）
module tb_key_events;

    localparam integer CLK_PERIOD = 10;   // 10ns = 100MHz 的外部时钟定义（计数按 CLOCK_MHZ 换算）

    reg  clk;
    reg  rst_n;
    reg  key;
    wire short_pulse;
    wire long_pulse;
    wire single_pulse;
    wire double_pulse;

    integer n_short, n_long, n_single, n_double;
    integer errors;

    key_events #(
        .CLOCK_MHZ   (1),
        .DEBOUNCE_MS (1),
        .LONG_MS     (5),
        .DOUBLE_MS   (6)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .button_in    (key),
        .short_pulse  (short_pulse),
        .long_pulse   (long_pulse),
        .single_pulse (single_pulse),
        .double_pulse (double_pulse)
    );

    // 1ms = 1000 拍（CLOCK_MHZ=1）
    task wait_ms(input integer ms);
        integer k;
        begin
            for (k = 0; k < ms * 1000; k = k + 1) @(posedge clk);
        end
    endtask

    task press_for(input integer ms);
        begin
            key = 1'b0;
            wait_ms(ms);
            key = 1'b1;
        end
    endtask

    always @(posedge clk) begin
        if (short_pulse)  n_short  = n_short  + 1;
        if (long_pulse)   n_long   = n_long   + 1;
        if (single_pulse) n_single = n_single + 1;
        if (double_pulse) n_double = n_double + 1;
    end

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        key   = 1'b1;
        n_short = 0; n_long = 0; n_single = 0; n_double = 0; errors = 0;

        wait_ms(2);
        rst_n = 1'b1;
        wait_ms(2);

        // ---- 场景 1：单击 ----
        press_for(2);
        wait_ms(10);                        // 2ms 按下 + 1ms 去抖 + 3ms 窗口 = 6ms，等 8ms 足够
        $display("  S1 单击: short=%0d single=%0d double=%0d long=%0d", n_short, n_single, n_double, n_long);
        if (n_short != 1 || n_single != 1 || n_double != 0 || n_long != 0) begin
            $display("  !! S1 失败"); errors = errors + 1;
        end
        n_short = 0; n_single = 0; n_double = 0; n_long = 0;

        // ---- 场景 2：双击 ----
        press_for(2);
        wait_ms(2);                       // 间隔 2ms：大于去抖 1ms、小于窗口 3ms
        press_for(2);
        wait_ms(10);
        $display("  S2 双击: short=%0d single=%0d double=%0d long=%0d", n_short, n_single, n_double, n_long);
        if (n_short != 2 || n_double != 1 || n_single != 0 || n_long != 0) begin
            $display("  !! S2 失败"); errors = errors + 1;
        end
        n_short = 0; n_single = 0; n_double = 0; n_long = 0;

        // ---- 场景 3：长按 ----
        press_for(6);                     // > 5ms 判长按
        wait_ms(10);
        $display("  S3 长按: short=%0d single=%0d double=%0d long=%0d", n_short, n_single, n_double, n_long);
        if (n_long != 1 || n_short != 0 || n_single != 0 || n_double != 0) begin
            $display("  !! S3 失败（长按不应产生短按/单击）"); errors = errors + 1;
        end
        n_short = 0; n_single = 0; n_double = 0; n_long = 0;

        // ---- 场景 4：抖动（200 拍内抖 5 次，短于去抖 2ms）----
        key = 1'b0; wait_ms(1); key = 1'b1; wait_ms(1);
        key = 1'b0; wait_ms(1); key = 1'b1; wait_ms(1);
        key = 1'b0; press_for(2);
        wait_ms(10);
        $display("  S4 抖动: short=%0d single=%0d double=%0d long=%0d", n_short, n_single, n_double, n_long);
        if (n_short != 1 || n_single != 1 || n_double != 0) begin
            $display("  !! S4 失败（抖动不应产生额外事件）"); errors = errors + 1;
        end

        $display("");
        if (errors == 0) $display("==== KEY_EVENTS TEST PASS ====");
        else             $display("==== KEY_EVENTS TEST FAIL (%0d) ====", errors);
        $finish;
    end

endmodule
