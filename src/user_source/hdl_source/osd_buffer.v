module osd_buffer (
    input  wire       clk,
    input  wire       rst,
    input  wire       wr_en,
    input  wire [7:0] wr_x,
    input  wire [6:0] wr_y,
    input  wire [1:0] wr_data,
    input  wire       rd_en,
    input  wire [7:0] rd_x,
    input  wire [6:0] rd_y,
    output wire [1:0] rd_data,
    output reg        rd_valid
);

    // 256 列 x 80 行 x 2bit。每块 BRAM9K 存 16 行（4096x2bit），共 5 块，
    // 用行高位选块：bank = y[6:4]，块内偏移 = {y[3:0], x[7:0]}（与扩容前地址完全一致）。
    wire [11:0] write_addr = {wr_y[3:0], wr_x};
    wire [11:0] read_addr  = {rd_y[3:0], rd_x};
    wire [2:0]  wr_bank    = wr_y[6:4];
    wire [2:0]  rd_bank    = rd_y[6:4];

    wire [1:0] memory_data;

    always @(posedge clk or posedge rst) begin
        if (rst)
            rd_valid <= 1'b0;
        else
            rd_valid <= rd_en;
    end

    // 读块号打一拍，与 BRAM 的 1 拍读延迟对齐
    reg [2:0] rd_bank_q;
    always @(posedge clk or posedge rst) begin
        if (rst)
            rd_bank_q <= 3'd0;
        else
            rd_bank_q <= rd_bank;
    end

`ifdef OSD_BUFFER_SIM
    reg [1:0] memory [0:20479];
    reg [1:0] memory_q;
    always @(posedge clk) begin
        if (wr_en)
            memory[{wr_y, wr_x}] <= wr_data;
        if (rd_en)
            memory_q <= memory[{rd_y, rd_x}];
    end
    assign memory_data = memory_q;
`else
    wire [1:0] q0, q1, q2, q3, q4;
    wire       we0 = wr_en && (wr_bank == 3'd0);
    wire       we1 = wr_en && (wr_bank == 3'd1);
    wire       we2 = wr_en && (wr_bank == 3'd2);
    wire       we3 = wr_en && (wr_bank == 3'd3);
    wire       we4 = wr_en && (wr_bank == 3'd4);

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(2), .ADDR_WIDTH_A(12), .DATA_DEPTH_A(4096),
        .DATA_WIDTH_B(2), .ADDR_WIDTH_B(12), .DATA_DEPTH_B(4096),
        .MODE("PDPW"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("ON"), .INIT_FILE("NONE"), .FILL_ALL("NONE"),
        .IMPLEMENT("9K")
    ) bank0 (
        .dia(wr_data), .addra(write_addr), .cea(we0), .ocea(1'b0),
        .clka(clk), .wea(we0), .rsta(1'b0), .bea(1'b0),
        .dib(2'd0), .addrb(read_addr), .ceb(rd_en), .oceb(1'b0),
        .clkb(clk), .web(1'b0), .rstb(1'b0), .beb(1'b0),
        .doa(), .dob(q0)
    );

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(2), .ADDR_WIDTH_A(12), .DATA_DEPTH_A(4096),
        .DATA_WIDTH_B(2), .ADDR_WIDTH_B(12), .DATA_DEPTH_B(4096),
        .MODE("PDPW"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("ON"), .INIT_FILE("NONE"), .FILL_ALL("NONE"),
        .IMPLEMENT("9K")
    ) bank1 (
        .dia(wr_data), .addra(write_addr), .cea(we1), .ocea(1'b0),
        .clka(clk), .wea(we1), .rsta(1'b0), .bea(1'b0),
        .dib(2'd0), .addrb(read_addr), .ceb(rd_en), .oceb(1'b0),
        .clkb(clk), .web(1'b0), .rstb(1'b0), .beb(1'b0),
        .doa(), .dob(q1)
    );

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(2), .ADDR_WIDTH_A(12), .DATA_DEPTH_A(4096),
        .DATA_WIDTH_B(2), .ADDR_WIDTH_B(12), .DATA_DEPTH_B(4096),
        .MODE("PDPW"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("ON"), .INIT_FILE("NONE"), .FILL_ALL("NONE"),
        .IMPLEMENT("9K")
    ) bank2 (
        .dia(wr_data), .addra(write_addr), .cea(we2), .ocea(1'b0),
        .clka(clk), .wea(we2), .rsta(1'b0), .bea(1'b0),
        .dib(2'd0), .addrb(read_addr), .ceb(rd_en), .oceb(1'b0),
        .clkb(clk), .web(1'b0), .rstb(1'b0), .beb(1'b0),
        .doa(), .dob(q2)
    );

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(2), .ADDR_WIDTH_A(12), .DATA_DEPTH_A(4096),
        .DATA_WIDTH_B(2), .ADDR_WIDTH_B(12), .DATA_DEPTH_B(4096),
        .MODE("PDPW"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("ON"), .INIT_FILE("NONE"), .FILL_ALL("NONE"),
        .IMPLEMENT("9K")
    ) bank3 (
        .dia(wr_data), .addra(write_addr), .cea(we3), .ocea(1'b0),
        .clka(clk), .wea(we3), .rsta(1'b0), .bea(1'b0),
        .dib(2'd0), .addrb(read_addr), .ceb(rd_en), .oceb(1'b0),
        .clkb(clk), .web(1'b0), .rstb(1'b0), .beb(1'b0),
        .doa(), .dob(q3)
    );

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(2), .ADDR_WIDTH_A(12), .DATA_DEPTH_A(4096),
        .DATA_WIDTH_B(2), .ADDR_WIDTH_B(12), .DATA_DEPTH_B(4096),
        .MODE("PDPW"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("ON"), .INIT_FILE("NONE"), .FILL_ALL("NONE"),
        .IMPLEMENT("9K")
    ) bank4 (
        .dia(wr_data), .addra(write_addr), .cea(we4), .ocea(1'b0),
        .clka(clk), .wea(we4), .rsta(1'b0), .bea(1'b0),
        .dib(2'd0), .addrb(read_addr), .ceb(rd_en), .oceb(1'b0),
        .clkb(clk), .web(1'b0), .rstb(1'b0), .beb(1'b0),
        .doa(), .dob(q4)
    );

    reg [1:0] bank_mux_q;
    always @(*) begin
        case (rd_bank_q)
            3'd0:    bank_mux_q = q0;
            3'd1:    bank_mux_q = q1;
            3'd2:    bank_mux_q = q2;
            3'd3:    bank_mux_q = q3;
            3'd4:    bank_mux_q = q4;
            default: bank_mux_q = 2'd0;
        endcase
    end
    assign memory_data = bank_mux_q;
`endif

    assign rd_data = rd_valid ? memory_data : 2'd0;

endmodule
