// 左上角信息条（V2）：显示页码 "PAGE n/4"，替代原 "SRC <W>X<H>"
// 缓冲区行 72、字符列 20~31（与右上角状态栏同行不同列）
module src_info_render (
    input  wire        clk,
    input  wire        rst,
    input  wire [1:0]  img_idx,
    input  wire [15:0] src_w,
    input  wire [15:0] src_h,
    output reg         req_valid,
    output wire [6:0]  req_ascii,
    output wire [7:0]  req_x,
    output wire [6:0]  req_y,
    output wire [1:0]  req_type,
    input  wire        req_ready,
    output wire        busy
);
    localparam [4:0] COL_BASE = 5'd20;
    localparam [6:0] ROW_LINE = 7'd72;
    localparam [2:0] S_IDLE = 3'd0, S_ISS = 3'd1, S_WAIT = 3'd2, S_NEXT = 3'd3;

    reg [95:0] msg;
    always @(*) begin
        case (img_idx)
            2'd0:    msg = "PAGE 1/4    ";
            2'd1:    msg = "PAGE 2/4    ";
            2'd2:    msg = "PAGE 3/4    ";
            default: msg = "PAGE 4/4    ";
        endcase
    end

    reg [1:0] idx_q;
    reg       booted;
    reg [3:0] col;
    reg [2:0] st;
    reg       dirty;
    reg [6:0] ascii_r;
    reg [7:0] x_r;
    reg [1:0] type_r;

    wire changed = !booted || (img_idx != idx_q);

    assign req_ascii = ascii_r;
    assign req_x     = x_r;
    assign req_y     = ROW_LINE;
    assign req_type  = type_r;
    assign busy      = (st != S_IDLE) || dirty;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            idx_q <= 2'd0; booted <= 1'b0; dirty <= 1'b1;
            st <= S_IDLE; col <= 4'd0; req_valid <= 1'b0;
            ascii_r <= 7'd0; x_r <= {3'd0, COL_BASE}; type_r <= 2'b10;
        end else begin
            if (changed) begin
                idx_q <= img_idx; booted <= 1'b1; dirty <= 1'b1;
            end
            case (st)
                S_IDLE: begin
                    req_valid <= 1'b0;
                    if (dirty) begin
                        dirty <= 1'b0; col <= 4'd0; st <= S_ISS;
                    end
                end
                S_ISS: begin
                    ascii_r   <= msg[95 - {col, 3'b000} -: 8];
                    x_r       <= {3'd0, COL_BASE} + {4'd0, col};
                    type_r    <= 2'b10;
                    req_valid <= 1'b1;
                    st        <= S_WAIT;
                end
                S_WAIT: begin
                    if (req_ready) begin
                        req_valid <= 1'b0; st <= S_NEXT;
                    end
                end
                S_NEXT: begin
                    if (col == 4'd11) st <= S_IDLE;
                    else begin col <= col + 4'd1; st <= S_ISS; end
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
