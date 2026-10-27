// 16x16 ASCII 点阵字库（V2-11 清晰字体）
// 字符范围 32~126（95 个），每字符 16 行、每行 16 bit
// 数据由 Pillow 从 Consolas 生成，见 font16_data.mif / font16_data.mem
// 地址：addr = (ascii - 32) * 16 + row，共 1520 字，按 2048 深度例化
module font16_rom (
    input  wire        clk,
    input  wire        rst,
    input  wire        rd_en,
    input  wire [6:0]  ascii,
    input  wire [3:0]  row,
    output wire [15:0] rd_data,
    output reg         rd_valid
);

    wire [10:0] address = {ascii[6:5], ascii[4:0], row} - 11'd512;   // (ascii-32)*16 + row
    wire        memory_en = rd_en && (ascii >= 7'd32);
    reg         in_range;
    wire [15:0] memory_data;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_valid <= 1'b0;
            in_range <= 1'b0;
        end else begin
            rd_valid <= rd_en;
            in_range <= memory_en;
        end
    end

`ifdef FONT16_ROM_SIM
    reg [15:0] memory [0:2047];
    reg [15:0] memory_q;
    initial $readmemh("font16_data.mem", memory);
    always @(posedge clk) begin
        if (memory_en)
            memory_q <= memory[address];
    end
    assign memory_data = memory_q;
`else
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(16), .ADDR_WIDTH_A(11), .DATA_DEPTH_A(2048),
        .DATA_WIDTH_B(16), .ADDR_WIDTH_B(11), .DATA_DEPTH_B(2048),
        .MODE("SP"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("OFF"), .INIT_FILE("../../user_source/hdl_source/font16_data.mif"),
        .FILL_ALL("NONE"), .IMPLEMENT("32K")   // 2048x16 = 32Kbit，正好一块 BRAM32K
    ) memory_inst (
        .dia(16'd0), .addra(address), .cea(memory_en), .ocea(1'b0),
        .clka(clk), .wea(1'b0), .rsta(1'b0), .bea(1'b0),
        .dib(16'd0), .addrb(11'd0), .ceb(1'b0), .oceb(1'b0),
        .clkb(clk), .web(1'b0), .rstb(1'b0), .beb(1'b0),
        .doa(memory_data), .dob()
    );
`endif

    assign rd_data = rd_valid && in_range ? memory_data : 16'd0;

endmodule
