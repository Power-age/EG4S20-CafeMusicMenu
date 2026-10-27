`timescale 1ns/1ps
// 三源仲裁器单元测试
module tb_sec_arbiter;
    reg clk, rst;
    reg scan_req, pic_req, wav_req, wav_allowed;
    reg sec_end, sec_timeout;
    wire [1:0] grant;
    wire gv;

    localparam [1:0] G_SCAN=2'd0, G_PIC=2'd1, G_WAV=2'd2;

    integer errors;

    sec_channel_arbiter dut(
        .clk(clk), .rst(rst),
        .scan_req(scan_req), .pic_req(pic_req),
        .wav_req(wav_req), .wav_allowed(wav_allowed),
        .sec_end(sec_end), .sec_timeout(sec_timeout),
        .grant(grant), .grant_valid(gv)
    );

    // 等待 grant 变成期望值
    task wait_grant; input [1:0] g; input [31:0] to;
        integer i;
        begin
            i=0;
            while ((grant!==g) && i<to) begin @(posedge clk); i=i+1; end
            if (grant!==g) begin
                $display("FAIL: wait_grant exp=%0d got=%0d", g, grant);
                errors=errors+1;
            end
        end
    endtask

    task wait_active; input a; input [31:0] to;
        integer i;
        begin
            i=0;
            while ((dut.active!==a) && i<to) begin @(posedge clk); i=i+1; end
            if (dut.active!==a) begin
                $display("FAIL: wait_active exp=%b got=%b", a, dut.active);
                errors=errors+1;
            end
        end
    endtask

    // 要求 grant 连续 n 拍保持 g
    task hold_grant; input [1:0] g; input integer n;
        integer i;
        begin
            for (i=0;i<n;i=i+1) begin
                @(posedge clk);
                if (grant!==g) begin
                    $display("FAIL: hold_grant exp=%0d got=%0d", g, grant);
                    errors=errors+1;
                end
            end
        end
    endtask

    task check_grant; input [1:0] g;
        if (grant!==g) begin
            $display("FAIL: check_grant exp=%0d got=%0d", g, grant);
            errors=errors+1;
        end
    endtask

    // 单拍释放脉冲：释放拍(posedge)只清 active，下一拍才按新请求裁决
    task pulse_end;
        begin
            @(negedge clk); sec_end=1'b1;
            @(posedge clk);                 // active<=0
            @(negedge clk); sec_end=1'b0;
        end
    endtask
    task pulse_timeout;
        begin
            @(negedge clk); sec_timeout=1'b1;
            @(posedge clk);
            @(negedge clk); sec_timeout=1'b0;
        end
    endtask

    initial clk=1'b0;
    always #5 clk=~clk;

    initial begin
        errors=0;
        rst=1'b1; scan_req=0; pic_req=0; wav_req=0; wav_allowed=0;
        sec_end=0; sec_timeout=0;
        repeat(3) @(posedge clk);
        rst=1'b0;
        repeat(2) @(posedge clk);
        $display("==== tb_sec_arbiter start ====");

        // S1: scan 请求 -> 授予 SCAN 并锁定
        scan_req=1'b1;
        wait_active(1'b1, 10);
        check_grant(G_SCAN);
        // 即使 PIC/WAV 都请求且 WAV 已允许，扫描仍独占
        pic_req=1'b1; wav_req=1'b1; wav_allowed=1'b1;
        hold_grant(G_SCAN, 5);

        // S2: 扇区结束、scan 仍连续请求 -> 回到 SCAN
        pulse_end;
        wait_active(1'b1, 10);
        check_grant(G_SCAN);

        // S3: scan 撤、PIC 请求 -> 切 PIC
        scan_req=1'b0;
        pulse_end;
        wait_grant(G_PIC, 10);
        wait_active(1'b1, 10);
        // WAV 在 PIC 读中请求，不得抢占
        hold_grant(G_PIC, 4);

        // S4: PIC 撤、WAV 在（已允许）-> 切 WAV
        pic_req=1'b0;
        pulse_end;
        wait_grant(G_WAV, 10);
        wait_active(1'b1, 10);
        hold_grant(G_WAV, 3);

        // S5: WAV 读中 PIC 又请求 -> 锁定 WAV 到 end，end 后才切 PIC
        pic_req=1'b1;
        hold_grant(G_WAV, 4);
        pulse_end;
        wait_grant(G_PIC, 10);

        // S6: PIC 读超时释放，此时仅 WAV 请求 -> 切 WAV
        pic_req=1'b0;
        pulse_timeout;
        wait_grant(G_WAV, 10);

        // S7: WAV 未被允许时，结束后通道应空闲（active=0），不授予 WAV
        wav_allowed=1'b0;
        pulse_end;
        wait_active(1'b0, 10);
        hold_grant(G_WAV, 3);          // grant 保持旧值，但 active=0
        // 一旦允许，立即授予 WAV
        wav_allowed=1'b1;
        wait_active(1'b1, 10);
        check_grant(G_WAV);

        // S8: 全部撤、结束 -> 通道空闲
        wav_req=1'b0;
        pulse_end;
        wait_active(1'b0, 10);

        repeat(5) @(posedge clk);
        if (errors==0) $display("==== tb_sec_arbiter PASS ====");
        else $display("==== tb_sec_arbiter FAIL errors=%0d ====", errors);
        $finish;
    end
endmodule
