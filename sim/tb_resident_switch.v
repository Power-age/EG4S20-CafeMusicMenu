`timescale 1ns/1ps
//  resident_switch 单元测试（任务 21 步骤 3）
module tb_resident_switch;
    reg clk = 0; always #20 clk = ~clk;     // 25MHz, T=40ns
    reg rst;
    reg frame_pulse, key_pulse, auto_en, all_resident, dir;
    reg [3:0] bank_valid;
    reg [1:0] cur_disp;
    wire [1:0] resident_idx;
    wire [1:0] target_wire;

    resident_switch #(.AUTO_TICKS(8)) dut (
        .clk(clk), .rst(rst), .frame_pulse(frame_pulse), .key_pulse(key_pulse),
        .auto_en(auto_en), .bank_valid(bank_valid), .all_resident(all_resident),
        .cur_disp(cur_disp), .dir(dir),
        .resident_idx(resident_idx), .target_out(target_wire)
    );

    task do_key; begin
        @(negedge clk); key_pulse = 1'b1; @(negedge clk); key_pulse = 1'b0;
    end endtask
    task do_frame; begin
        @(negedge clk); frame_pulse = 1'b1; @(negedge clk); frame_pulse = 1'b0;
    end endtask

    integer fails = 0;
    task check; input [127:0] name; input [1:0] exp; begin
        if (resident_idx !== exp) begin
            $display("FAIL %-22s got=%0d exp=%0d", name, resident_idx, exp);
            fails = fails + 1;
        end
        else $display("ok   %-22s =%0d", name, resident_idx);
    end endtask

    initial begin
        rst = 1; frame_pulse = 0; key_pulse = 0; auto_en = 0;
        all_resident = 0; dir = 0; bank_valid = 4'b1111; cur_disp = 0;
        repeat (3) @(negedge clk); rst = 0; repeat (2) @(negedge clk);

        // ---- S1: 全好正向手动；帧中按键不立即切，frame 后才切（不撕裂）----
        all_resident = 1; bank_valid = 4'b1111; dir = 0;
        @(negedge clk);
        do_key;
        check("S1 key, no frame", 2'd0);
        if (target_wire !== 2'd1) begin
            $display("FAIL S1 target after key  =%0d exp=1", target_wire); fails = fails + 1;
        end
        else $display("ok   S1 target after key     =1");
        do_frame; check("S1 frame ->1", 2'd1);
        do_key; do_frame; check("S1 ->2", 2'd2);
        do_key; do_frame; check("S1 ->3", 2'd3);
        do_key; do_frame; check("S1 wrap ->0", 2'd0);

        // ---- S2: bv=1101，跳过 idx1 ----
        all_resident = 0; @(negedge clk);
        all_resident = 1; bank_valid = 4'b1101;
        do_key; do_frame; check("S2 0->2", 2'd2);
        do_key; do_frame; check("S2 2->3", 2'd3);
        do_key; do_frame; check("S2 3->0", 2'd0);

        // ---- S3: 反向 dir=1，全好 ----
        all_resident = 0; dir = 1; @(negedge clk);
        all_resident = 1; bank_valid = 4'b1111;
        do_key; do_frame; check("S3 0->3", 2'd3);
        do_key; do_frame; check("S3 3->2", 2'd2);
        do_key; do_frame; check("S3 2->1", 2'd1);
        do_key; do_frame; check("S3 1->0", 2'd0);

        // ---- S4: 自动播放，AUTO_TICKS=8 ----
        all_resident = 0; dir = 0; @(negedge clk);
        all_resident = 1; bank_valid = 4'b1111;
        auto_en = 1;
        repeat (8) @(negedge clk);
        check("S4 ticks, no frame", 2'd0);
        do_frame; check("S4 frame ->1", 2'd1);
        auto_en = 0;

        // ---- S5: 接管初始化，首好图 cur_disp=2 ----
        all_resident = 0; cur_disp = 2; bank_valid = 4'b1101;
        repeat (2) @(negedge clk);
        check("S5 follow cur 2", 2'd2);
        all_resident = 1;
        do_frame; check("S5 stays 2", 2'd2);
        do_key; do_frame; check("S5 2->3", 2'd3);

        if (fails == 0) $display("=== ALL RESIDENT_SWITCH TESTS PASS ===");
        else $display("=== %0d FAILURE(S) ===", fails);
        $finish;
    end
endmodule
