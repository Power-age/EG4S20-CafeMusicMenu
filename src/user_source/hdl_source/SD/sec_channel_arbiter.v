`timescale 1ns / 1ps
// ============================================================================
//  File        : sec_channel_arbiter.v
//  Description : SD 单扇区读通道三源仲裁
//                物理上只有一条 SD 单块读通道，三个请求源：
//                  G_SCAN : FAT32 卷扫描器（上电扫描，最高优先）
//                  G_PIC  : 图片簇链 chain_reader（装载四图，次优先）
//                  G_WAV  : WAV 簇链 chain_reader（常驻完成后才允许，最低优先）
//                仲裁规则：
//                  - 通道空闲时按 SCAN > PIC > WAV 裁决并锁定；
//                  - 一旦授予某源，锁定到该扇区 sec_end / sec_timeout；
//                  - sec_end / sec_timeout 当拍“只释放、不立即重锁”，下一拍再按
//                    已更新的请求裁决——避免采到源在结束当拍被清掉的旧请求而把
//                    通道锁给一个已经结束的源（死锁）；
//                  - 三个请求均接各源“实际物理读请求电平”，不接阶段电平；
//                  - WAV 仅在 wav_allowed（四图常驻 all_resident）后才可获得通道。
// ============================================================================
module sec_channel_arbiter (
    input  wire       clk,
    input  wire       rst,

    input  wire       scan_req,      // 扫描器实际物理读请求
    input  wire       pic_req,       // 图片 chain 的物理读请求
    input  wire       wav_req,       // WAV  chain 的物理读请求
    input  wire       wav_allowed,   // 允许 WAV 占用（all_resident）

    input  wire       sec_end,       // 当前扇区读结束
    input  wire       sec_timeout,   // 当前扇区读超时

    output reg  [1:0] grant,
    output wire       grant_valid
);

    localparam [1:0] G_SCAN = 2'd0;
    localparam [1:0] G_PIC  = 2'd1;
    localparam [1:0] G_WAV  = 2'd2;

    reg active;
    wire rel;

    assign rel = sec_end || sec_timeout;
    assign grant_valid = active;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            active <= 1'b0;
            grant  <= G_SCAN;
        end else begin
            if (active && rel) begin
                // 结束当拍只释放，不立即重锁
                active <= 1'b0;
            end else if (!active) begin
                // 通道确实空闲时，按优先级裁决
                if (scan_req) begin
                    grant  <= G_SCAN;
                    active <= 1'b1;
                end else if (pic_req) begin
                    grant  <= G_PIC;
                    active <= 1'b1;
                end else if (wav_allowed && wav_req) begin
                    grant  <= G_WAV;
                    active <= 1'b1;
                end
                // 无任何请求：active 保持 0，grant 保持
            end
            // active && !rel：扇区读进行中，锁定不动
        end
    end

endmodule
