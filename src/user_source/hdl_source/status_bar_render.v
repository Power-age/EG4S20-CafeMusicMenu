// 右上角信息条（V5）：歌名 + 曲目倒计时，5×7 手绘字体
//
// 内容：20 字符 = 歌名（12 字符，来自 track_names.mif）+ " -MM:SS"
// 位置：buffer 行 72，字符列 0~19（覆盖层映射到屏幕右上角 x 312~632、y 12~26）
// 发送时逐字符读 ROM；倒计时数值在突发开始时快照，避免半行刷新。
// 没有音乐在放时时间字段显示 " --:-- "。
module status_bar_render (
    input  wire        clk,
    input  wire        rst,
    input  wire [3:0]  track_idx,
    input  wire        cd_active,
    input  wire [6:0]  cd_min,
    input  wire [5:0]  cd_sec,
    output reg         req_valid,
    output reg  [6:0]  req_ascii,
    output wire [7:0]  req_x,
    output wire [6:0]  req_y,
    output wire [1:0]  req_type,
    input  wire        req_ready
);

    localparam [4:0] COL_MAX = 5'd19;
    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_RD   = 3'd1;
    localparam [2:0] S_ISS  = 3'd2;
    localparam [2:0] S_WAIT = 3'd3;

    // ---------------- 曲名 ROM（16 槽 × 16 字符） ----------------
    reg  [4:0] col;
    reg  [3:0] idx_q;
    wire [7:0] nm_addr = {idx_q, col[3:0]};
    wire [7:0] nm_d;

`ifdef TRACK_NAMES_SIM
    reg [7:0] tnam [0:255];
    reg [7:0] tnam_q;
    initial $readmemh("track_names.mem", tnam);
    always @(posedge clk) tnam_q <= tnam[nm_addr];
    assign nm_d = tnam_q;
`else
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(8), .ADDR_WIDTH_A(8), .DATA_DEPTH_A(256),
        .DATA_WIDTH_B(8), .ADDR_WIDTH_B(8), .DATA_DEPTH_B(256),
        .MODE("SP"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("ON"), .INIT_FILE("../../user_source/hdl_source/track_names.mif"),
        .FILL_ALL("NONE"), .IMPLEMENT("9K")
    ) u_tnam_rom (
        .dia(8'd0), .addra(nm_addr), .cea(1'b1), .ocea(1'b0),
        .clka(clk), .wea(1'b0), .rsta(1'b0), .bea(1'b0),
        .dib(8'd0), .addrb(8'd0), .ceb(1'b0), .oceb(1'b0),
        .clkb(clk), .web(1'b0), .rstb(1'b0), .beb(1'b0),
        .doa(nm_d), .dob()
    );
`endif

    // ---------------- 倒计时快照 ----------------
    reg [6:0] snap_min;
    reg [5:0] snap_sec;
    reg       snap_act;
    reg       booted;
    reg [2:0] st;

    wire changed = (cd_min != snap_min) || (cd_sec != snap_sec) || (cd_active != snap_act);
    wire dirty   = !booted || (track_idx != idx_q) || changed;

    wire [3:0] mm_t = snap_min / 10;
    wire [3:0] mm_o = snap_min % 10;
    wire [3:0] ss_t = snap_sec / 10;
    wire [3:0] ss_o = snap_sec % 10;

    reg [6:0] tchar;
    always @(*) begin
        case (col)
            5'd12: tchar = 7'd32;                                    // 空格
            5'd13: tchar = 7'd45;                                    // '-'
            5'd14: tchar = snap_act ? (7'd48 + {3'd0, mm_t}) : 7'd45;
            5'd15: tchar = snap_act ? (7'd48 + {3'd0, mm_o}) : 7'd58;
            5'd16: tchar = 7'd58;                                    // ':'
            5'd17: tchar = snap_act ? (7'd48 + {3'd0, ss_t}) : 7'd45;
            5'd18: tchar = snap_act ? (7'd48 + {3'd0, ss_o}) : 7'd45;
            default: tchar = 7'd32;
        endcase
    end

    assign req_x    = {3'd0, col};
    assign req_y    = 7'd72;
    assign req_type = 2'b10;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            col       <= 5'd0;
            idx_q     <= 4'd0;
            st        <= S_IDLE;
            booted    <= 1'b0;
            snap_min  <= 7'd0;
            snap_sec  <= 6'd0;
            snap_act  <= 1'b0;
            req_valid <= 1'b0;
            req_ascii <= 7'd32;
        end else begin
            case (st)
                S_IDLE: begin
                    req_valid <= 1'b0;
                    if (dirty) begin
                        col       <= 5'd0;
                        idx_q     <= track_idx;
                        snap_min  <= cd_min;
                        snap_sec  <= cd_sec;
                        snap_act  <= cd_active;
                        booted    <= 1'b1;
                        st        <= S_RD;
                    end
                end
                S_RD: begin
                    st <= S_ISS;
                end
                S_ISS: begin
                    req_valid <= 1'b1;
                    req_ascii <= (col < 5'd12) ? nm_d[6:0] : tchar;
                    st        <= S_WAIT;
                end
                S_WAIT: begin
                    if (req_ready) begin
                        req_valid <= 1'b0;
                        if (col == COL_MAX) st <= S_IDLE;
                        else begin
                            col <= col + 5'd1;
                            st  <= S_RD;
                        end
                    end
                end
                default: st <= S_IDLE;
            endcase
        end
    end

endmodule
