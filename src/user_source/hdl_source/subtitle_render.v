// 图片说明字幕渲染（V5）：每张图一句话，6 字符窗口逐字符滚动、循环播放
//
// 缓冲区位置：字符列 6~11（buffer 列 48~95）、行 60~66
// 覆盖层对应的屏幕窗口：x 272~367、y 400~413
// 文本来源：ticker_text.mif（4 槽 × 64 字符，每槽前 48 字符为字幕内容，其余补空格）
module subtitle_render (
    input  wire       clk,
    input  wire       rst,
    input  wire       vis,         // 面板关闭时为 1
    input  wire       buf_ready,
    input  wire       vs,
    input  wire [1:0] img_idx,
    output reg        req_valid,
    output reg  [6:0] req_ascii,
    output wire [7:0] req_x,
    output wire [6:0] req_y,
    output wire [1:0] req_type,
    output reg        req_fill,
    input  wire       req_ready,
    output wire       busy
);

    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_RD   = 3'd1;
    localparam [2:0] S_ISS  = 3'd2;
    localparam [2:0] S_WAIT = 3'd3;
    localparam [2:0] S_GAP  = 3'd4;

    localparam [5:0] START_TICK = 6'd32;  // 文案从窗口左外侧开始（整条滑入）
    localparam [3:0] FRAMES = 4'd4;   // 每 4 帧挪一个字符 ≈ 15 字符/秒，观感接近连续

    reg [2:0] st;
    reg [4:0] pos;
    reg [5:0] tick;
    reg [3:0] fcnt;
    reg       vs_q;
    reg [1:0] img_q;
    reg       fill_mode;
    reg       drawn;
    reg       cleared;

    wire        vs_rise     = vs & ~vs_q;
    wire        img_changed = (img_idx != img_q);
    wire [7:0]  rom_addr    = {img_q, (tick + pos)};
    wire [7:0]  rom_d;

`ifdef TICKER_ROM_SIM
    reg [7:0] tmem [0:255];
    reg [7:0] tmem_q;
    initial $readmemh("ticker_text.mem", tmem);
    always @(posedge clk) tmem_q <= tmem[rom_addr];
    assign rom_d = tmem_q;
`else
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(8), .ADDR_WIDTH_A(8), .DATA_DEPTH_A(256),
        .DATA_WIDTH_B(8), .ADDR_WIDTH_B(8), .DATA_DEPTH_B(256),
        .MODE("SP"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("ON"), .INIT_FILE("../../user_source/hdl_source/ticker_text.mif"),
        .FILL_ALL("NONE"), .IMPLEMENT("9K")
    ) u_ticker_rom (
        .dia(8'd0), .addra(rom_addr), .cea(1'b1), .ocea(1'b0),
        .clka(clk), .wea(1'b0), .rsta(1'b0), .bea(1'b0),
        .dib(8'd0), .addrb(8'd0), .ceb(1'b0), .oceb(1'b0),
        .clkb(clk), .web(1'b0), .rstb(1'b0), .beb(1'b0),
        .doa(rom_d), .dob()
    );
`endif

    assign busy     = (st == S_RD) || (st == S_ISS) || (st == S_WAIT);
    assign req_x    = {3'd0, pos};
    // 2026/10/24：存储行由 60 改到 0，避免与设置面板（行 8~71）重叠
    // ——面板打开时字幕清空自己的行，曾把菜单最后一行（行 64~70）的上半截擦掉
    assign req_y    = 7'd0;
    assign req_type = fill_mode ? 2'b00 : 2'b10;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            st        <= S_IDLE;
            pos       <= 3'd0;
            tick      <= START_TICK;
            fcnt      <= 4'd0;
            vs_q      <= 1'b0;
            img_q     <= 2'd0;
            fill_mode <= 1'b0;
            drawn     <= 1'b0;
            cleared   <= 1'b1;
            req_valid <= 1'b0;
            req_ascii <= 7'd32;
            req_fill  <= 1'b0;
        end else begin
            vs_q <= vs;
            if (img_changed) img_q <= img_idx;

            case (st)
                S_IDLE: begin
                    req_valid <= 1'b0;
                    req_fill  <= 1'b0;
                    if (!vis) begin
                        drawn <= 1'b0;
                        if (!cleared) begin
                            fill_mode <= 1'b1;
                            pos       <= 5'd0;
                            st        <= S_ISS;
                        end
                    end else begin
                        cleared <= 1'b0;
                        if (buf_ready && (!drawn || img_changed)) begin
                            fill_mode <= 1'b0;
                            pos       <= 5'd0;
                            if (img_changed) tick <= START_TICK;
                            st        <= S_RD;
                        end
                    end
                end
                S_RD: begin
                    st <= S_ISS;
                end
                S_ISS: begin
                    req_valid <= 1'b1;
                    req_ascii <= fill_mode ? 7'd32 : rom_d[6:0];
                    req_fill  <= fill_mode;
                    st        <= S_WAIT;
                end
                S_WAIT: begin
                    if (req_ready) begin
                        req_valid <= 1'b0;
                        req_fill  <= 1'b0;
                        if (pos == 5'd31) begin
                            if (fill_mode) begin
                                cleared <= 1'b1;
                                st      <= S_IDLE;
                            end else begin
                                drawn <= 1'b1;
                                fcnt  <= 4'd0;
                                st    <= S_GAP;
                            end
                        end else begin
                            pos <= pos + 5'd1;
                            st  <= fill_mode ? S_ISS : S_RD;
                        end
                    end
                end
                S_GAP: begin
                    if (img_changed) begin
                        tick  <= START_TICK;      // 切图后从末尾滚入
                        pos   <= 5'd0;
                        drawn <= 1'b0;
                        st    <= S_RD;
                    end else if (!vis) begin
                        st <= S_IDLE;
                    end else if (vs_rise && (tick != 6'd0)) begin
                        // 滚到 tick=0（文案开头对齐窗口左端）即停住，不再滚动
                        if (fcnt >= (FRAMES - 4'd1)) begin
                            fcnt <= 4'd0;
                            pos  <= 5'd0;
                            tick <= tick - 6'd1;
                            st   <= S_RD;
                        end else fcnt <= fcnt + 4'd1;
                    end
                end
                default: st <= S_IDLE;
            endcase
        end
    end

endmodule
