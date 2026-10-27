`timescale 1ns/1ps
// ============================================================================
//  resident_switch : 常驻帧缓存显示切换（任务 21 步骤 3）
//   - 手动 / 自动切图请求先更新"挂起目标图号" resident_req
//   - 仅在帧消隐 tick (frame_pulse, vsync 帧边界) 才把目标提交给读 bank
//     => 图已常驻：零加载延迟；帧中途不切：不撕裂
//   - 按方向循环，自动跳过坏 / 缺 bank
//   本模块位于 video_clk 域；所有输入均应由上层同步到本时钟域。
// ============================================================================
module resident_switch #
(
    parameter integer AUTO_TICKS = 25_000_000      // 自动播放间隔：1s @25MHz
)
(
    input               clk,
    input               rst,
    input               frame_pulse,    // vsync 帧边界 tick
    input               key_pulse,      // 手动切图（已在本时钟域消抖）
    input               auto_en,        // 自动播放使能（已同步）
    input       [31:0]  auto_ticks_i,   // 自动轮播间隔（周期数，运行时可变）
    input       [3:0]   bank_valid,     // 各 bank 是否有效（已同步）
    input               all_resident,   // 4 图装载完成（已同步）
    input       [1:0]   cur_disp,       // 接管前当前显示图号
    input               dir,            // 0=正向 / 1=反向（已同步）
    output reg  [1:0]   resident_idx,   // 当前应显示的 bank（硬切，接 frame_read_buf_idx）
    output      [1:0]   target_out      // 挂起目标图号（转场映射用）
);
    reg [1:0]   resident_req;
    reg [31:0]  timer;

    assign target_out = resident_req;

    // 从 cur 按方向遍历 4 个位置（含回到自己），找下一个有效 bank
    function [1:0] next_valid;
        input [1:0] cur;
        input [3:0] bv;
        input       d;
        integer     i;
        reg   [1:0] cand;
        reg         found;
        begin
            found      = 1'b0;
            next_valid = cur;
            for (i = 1; i <= 4; i = i + 1) begin
                if (d == 1'b0)
                    cand = cur + i[1:0];
                else
                    cand = cur - i[1:0];
                if (found == 1'b0 && bv[cand] == 1'b1) begin
                    next_valid = cand;
                    found      = 1'b1;
                end
            end
        end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            resident_idx <= 2'd0;
            resident_req <= 2'd0;
            timer        <= 32'd0;
        end
        else if (all_resident == 1'b0) begin
            // 接管前预载当前显示图号，保证 all_resident 拉高瞬间无跳变
            resident_idx <= cur_disp;
            resident_req <= cur_disp;
            timer        <= 32'd0;
        end
        else begin
            // 手动：立即更新挂起目标
            if (key_pulse)
                resident_req <= next_valid(resident_req, bank_valid, dir);

            // 自动：计满 AUTO_TICKS 更新挂起目标
            if (auto_en) begin
                if (timer >= auto_ticks_i - 32'd1) begin
                    timer        <= 32'd0;
                    resident_req <= next_valid(resident_req, bank_valid, dir);
                end
                else
                    timer <= timer + 32'd1;
            end
            else begin
                timer <= 32'd0;
            end

            // 帧消隐才正式提交显示 bank
            if (frame_pulse)
                resident_idx <= resident_req;
        end
    end
endmodule
