`timescale 1ns/1ps
//============================================================================
// tb_key_longshort.v
// 验证 key_longshort：
//   场景1 短按：按住时长 < LONG_CYCLES -> 恰好 1 个 short_pulse、无 long_repeat、
//               long_active 从未拉高。
//   场景2 长按（REPEAT_ENABLE=0）：按住达 LONG_CYCLES 并保持 -> long_active 拉高、
//               恰好 1 个 long_repeat、short_pulse 不出现；松手不发 short。
// 为加速仿真，覆盖：DEBOUNCE_MS=1（消抖约 12000 拍）、LONG=40000、REPEAT=10000。
//============================================================================
module tb_key_longshort;

    reg clk;
    reg rst_n;
    reg button;

    wire short_pulse;
    wire long_repeat;
    wire long_active;

    // 统计
    integer short_cnt = 0;
    integer rep_cnt   = 0;
    reg     saw_long  = 1'b0;

    always #41 clk = ~clk;   // 周期 82ns ~= 12.2MHz

    key_longshort
    #(
        .DEBOUNCE_MS   (1),
        .LONG_CYCLES   (40000),
        .REPEAT_CYCLES (10000),
        .REPEAT_ENABLE (0)
    )
    dut
    (
        .clk         (clk),
        .rst_n       (rst_n),
        .button_in   (button),
        .short_pulse (short_pulse),
        .long_repeat (long_repeat),
        .long_active (long_active)
    );

    always @(posedge clk) begin
        if (rst_n) begin
            if (short_pulse) short_cnt <= short_cnt + 1;
            if (long_repeat) rep_cnt   <= rep_cnt   + 1;
            if (long_active) saw_long  <= 1'b1;
        end
    end

    integer s1_short, s1_rep, d_short, d_rep;
    integer errors = 0;

    initial begin
        // 初始化
        clk    = 0;
        button = 1;     // 空闲为高
        rst_n  = 0;
        repeat (200) @(posedge clk);
        rst_n  = 1;
        repeat (2000) @(posedge clk);

        // -------- 场景1：短按 --------
        // 消抖约 12000 拍后 key_lvl 才变低；再保持 100 拍（< LONG 200）后松开
        @(negedge clk);
        button = 0;
        repeat (27000) @(posedge clk);
        button = 1;
        // 松开消抖约 12000 拍后 key_lvl 回高、产生 short
        repeat (26000) @(posedge clk);

        s1_short = short_cnt;
        s1_rep   = rep_cnt;
        $display("[S1 short] short=%0d repeat=%0d saw_long=%b", s1_short, s1_rep, saw_long);
        if (s1_short !== 1) begin $display("  FAIL: expect 1 short_pulse"); errors=errors+1; end
        if (s1_rep   !== 0) begin $display("  FAIL: expect 0 long_repeat"); errors=errors+1; end
        if (saw_long !== 1'b0) begin $display("  FAIL: long_active must stay low"); errors=errors+1; end

        repeat (2000) @(posedge clk);

        // -------- 场景2：长按 --------
        // key_lvl 低持续 = 200(达long) + 60*5 = 500 拍；button 低 = 12000 + 500 + 余量
        @(negedge clk);
        button = 0;
        repeat (82000) @(posedge clk);
        button = 1;
        repeat (26000) @(posedge clk);

        d_short = short_cnt - s1_short;
        d_rep   = rep_cnt   - s1_rep;
        $display("[S2 long ] d_short=%0d d_repeat=%0d saw_long=%b", d_short, d_rep, saw_long);
        if (saw_long !== 1'b1) begin $display("  FAIL: long_active must go high"); errors=errors+1; end
        if (d_short !== 0)     begin $display("  FAIL: long press must not emit short"); errors=errors+1; end
        if (d_rep   != 1)      begin $display("  FAIL: expect exactly 1 long_repeat, got %0d", d_rep); errors=errors+1; end

        repeat (1000) @(posedge clk);

        if (errors == 0)
            $display("==== KEY_LONGSHORT TEST PASS ====");
        else
            $display("==== KEY_LONGSHORT TEST FAIL (%0d errors) ====", errors);
        $finish;
    end

    // 超时保护
    initial begin
        #200_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
