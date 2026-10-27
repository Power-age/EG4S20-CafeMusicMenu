module waveform_ram (
    input  wire       clk,
    input  wire       rst,
    input  wire       wr_en,
    input  wire [9:0] wr_addr,
    input  wire [7:0] wr_data,
    input  wire       block_done,
    input  wire       frame_pulse,
    input  wire       video_de,
    output wire       block_accept,
    output reg        front_valid,
    output reg        front_sel,
    input  wire       rd_en,
    input  wire [9:0] rd_addr,
    output wire [7:0] rd_data,
    output reg        rd_valid
);

    localparam F_IDLE = 4'd0;
    localparam F_REQ_CENTER = 4'd1;
    localparam F_CAP_CENTER = 4'd2;
    localparam F_REQ_RIGHT = 4'd3;
    localparam F_CAP_RIGHT = 4'd4;
    localparam F_WRITE = 4'd5;
    localparam F_PAUSE = 4'd6;

    reg [3:0] filter_state;
    reg back_pending;
    reg [9:0] filter_addr;
    reg [7:0] raw_left;
    reg [7:0] raw_center;
    reg [7:0] raw_right;

    wire write_bank = ~front_sel;
    wire filter_active = (filter_state != F_IDLE);
    wire capture_we = wr_en && block_accept;
    wire filter_we = (filter_state == F_WRITE);
    wire [9:0] write_addr_mux = filter_we ? filter_addr : wr_addr;
    wire [7:0] write_data_mux;
    wire bank0_we = (capture_we && (write_bank == 1'b0)) ||
                    (filter_we && (write_bank == 1'b0));
    wire bank1_we = (capture_we && (write_bank == 1'b1)) ||
                    (filter_we && (write_bank == 1'b1));

    wire filter_read = (filter_state == F_REQ_CENTER) ||
                       (filter_state == F_REQ_RIGHT);
    wire [9:0] back_read_addr = (filter_state == F_REQ_RIGHT) ?
                                ((filter_addr == 10'd639) ? 10'd639 : filter_addr + 10'd1) :
                                filter_addr;
    wire [9:0] read_addr_mux = filter_read ? back_read_addr : rd_addr;
    wire bank0_re = filter_read ? 1'b1 :
                    (rd_en && front_valid && (front_sel == 1'b0));
    wire bank1_re = filter_read ? 1'b1 :
                    (rd_en && front_valid && (front_sel == 1'b1));
    wire [7:0] bank0_rd_data;
    wire [7:0] bank1_rd_data;
    wire [7:0] back_read_data = front_sel ? bank0_rd_data : bank1_rd_data;

    wire [9:0] spatial_sum = {2'd0, raw_left} +
                             {1'd0, raw_center, 1'b0} +
                             {2'd0, raw_right} + 10'd2;
    wire [7:0] spatial_value = spatial_sum[9:2];

    assign write_data_mux = spatial_value;
    assign block_accept = (filter_state == F_IDLE) && !back_pending;

    reg front_sel_d;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_valid <= 1'b0;
            front_sel_d <= 1'b0;
        end else begin
            rd_valid <= rd_en && front_valid && !filter_active;
            if (rd_en && front_valid && !filter_active)
                front_sel_d <= front_sel;
        end
    end
    assign rd_data = front_sel_d ? bank1_rd_data : bank0_rd_data;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            filter_state <= F_IDLE;
            back_pending <= 1'b0;
            filter_addr <= 10'd0;
            front_valid <= 1'b0;
            front_sel <= 1'b0;
            raw_left <= 8'd0;
            raw_center <= 8'd0;
            raw_right <= 8'd0;
        end else begin
            case (filter_state)
                F_IDLE: begin
                    if (block_done) begin
                        back_pending <= 1'b1;
                        if (!video_de) begin
                            filter_addr <= 10'd0;
                            filter_state <= F_REQ_CENTER;
                        end
                    end else if (back_pending && frame_pulse && !video_de) begin
                        filter_addr <= 10'd0;
                        filter_state <= F_REQ_CENTER;
                    end
                end
                F_REQ_CENTER: filter_state <= F_CAP_CENTER;
                F_CAP_CENTER: begin
                    raw_center <= back_read_data;
                    if (filter_addr == 10'd0)
                        raw_left <= back_read_data;
                    filter_state <= F_REQ_RIGHT;
                end
                F_REQ_RIGHT: filter_state <= F_CAP_RIGHT;
                F_CAP_RIGHT: begin
                    raw_right <= back_read_data;
                    filter_state <= F_WRITE;
                end
                F_WRITE: begin
                    if (filter_addr == 10'd639) begin
                        if (video_de) begin
                            back_pending <= 1'b1;
                            filter_state <= F_PAUSE;
                        end else begin
                            front_sel <= ~front_sel;
                            front_valid <= 1'b1;
                            back_pending <= 1'b0;
                            filter_addr <= 10'd0;
                            filter_state <= F_IDLE;
                        end
                    end else begin
                        raw_left <= raw_center;
                        filter_addr <= filter_addr + 10'd1;
                        if (video_de) begin
                            back_pending <= 1'b1;
                            filter_state <= F_PAUSE;
                        end else begin
                            filter_state <= F_REQ_CENTER;
                        end
                    end
                end
                default: begin
                    if (!video_de)
                        filter_state <= (filter_addr == 10'd639) ? F_WRITE : F_REQ_CENTER;
                end
            endcase
        end
    end

`ifdef WAVEFORM_RAM_SIM
    reg [7:0] bank0 [0:1023];
    reg [7:0] bank1 [0:1023];
    reg [7:0] bank0_q;
    reg [7:0] bank1_q;
    always @(posedge clk) begin
        if (bank0_we)
            bank0[write_addr_mux] <= filter_we ? spatial_value : wr_data;
        if (bank1_we)
            bank1[write_addr_mux] <= filter_we ? spatial_value : wr_data;
        if (bank0_re)
            bank0_q <= bank0[read_addr_mux];
        if (bank1_re)
            bank1_q <= bank1[read_addr_mux];
    end
    assign bank0_rd_data = bank0_q;
    assign bank1_rd_data = bank1_q;
`else
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(8), .ADDR_WIDTH_A(10), .DATA_DEPTH_A(1024),
        .DATA_WIDTH_B(8), .ADDR_WIDTH_B(10), .DATA_DEPTH_B(1024),
        .MODE("PDPW"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("OFF"), .INIT_FILE("NONE"), .FILL_ALL("NONE"),
        .IMPLEMENT("9K")
    ) bank0_mem (
        .dia(filter_we ? spatial_value : wr_data), .addra(write_addr_mux),
        .cea(bank0_we), .ocea(1'b0), .clka(clk), .wea(bank0_we),
        .rsta(1'b0), .bea(1'b0), .dib(8'd0), .addrb(read_addr_mux),
        .ceb(bank0_re), .oceb(1'b0), .clkb(clk), .web(1'b0),
        .rstb(1'b0), .beb(1'b0), .doa(), .dob(bank0_rd_data)
    );

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(8), .ADDR_WIDTH_A(10), .DATA_DEPTH_A(1024),
        .DATA_WIDTH_B(8), .ADDR_WIDTH_B(10), .DATA_DEPTH_B(1024),
        .MODE("PDPW"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("OFF"), .INIT_FILE("NONE"), .FILL_ALL("NONE"),
        .IMPLEMENT("9K")
    ) bank1_mem (
        .dia(filter_we ? spatial_value : wr_data), .addra(write_addr_mux),
        .cea(bank1_we), .ocea(1'b0), .clka(clk), .wea(bank1_we),
        .rsta(1'b0), .bea(1'b0), .dib(8'd0), .addrb(read_addr_mux),
        .ceb(bank1_re), .oceb(1'b0), .clkb(clk), .web(1'b0),
        .rstb(1'b0), .beb(1'b0), .doa(), .dob(bank1_rd_data)
    );
`endif

endmodule
