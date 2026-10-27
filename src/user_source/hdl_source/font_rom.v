module font_rom (
    input  wire       clk,
    input  wire       rst,
    input  wire       rd_en,
    input  wire [6:0] ascii,
    input  wire [2:0] row,
    output wire [7:0] rd_data,
    output reg        rd_valid
);

    wire [9:0] address = {ascii, row};
    wire memory_en = rd_en && (ascii >= 7'd32);
    reg in_range;
    wire [7:0] memory_data;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_valid <= 1'b0;
            in_range <= 1'b0;
        end else begin
            rd_valid <= rd_en;
            in_range <= memory_en;
        end
    end

`ifdef FONT_ROM_SIM
    reg [7:0] memory [0:1023];
    reg [7:0] memory_q;
    initial $readmemh("font_data.mem", memory);
    always @(posedge clk) begin
        if (memory_en)
            memory_q <= memory[address];
    end
    assign memory_data = memory_q;
`else
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(8), .ADDR_WIDTH_A(10), .DATA_DEPTH_A(1024),
        .DATA_WIDTH_B(8), .ADDR_WIDTH_B(10), .DATA_DEPTH_B(1024),
        .MODE("SP"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("ON"), .INIT_FILE("../../user_source/hdl_source/font_data.mif"),
        .FILL_ALL("NONE"), .IMPLEMENT("9K")
    ) memory_inst (
        .dia(8'd0), .addra(address), .cea(memory_en), .ocea(1'b0),
        .clka(clk), .wea(1'b0), .rsta(1'b0), .bea(1'b0),
        .dib(8'd0), .addrb(10'd0), .ceb(1'b0), .oceb(1'b0),
        .clkb(clk), .web(1'b0), .rstb(1'b0), .beb(1'b0),
        .doa(memory_data), .dob()
    );
`endif

    assign rd_data = rd_valid && in_range ? memory_data : 8'd0;

endmodule
