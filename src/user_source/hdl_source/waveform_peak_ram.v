module waveform_peak_ram (
    input  wire       clk,
    input  wire       rst,
    input  wire       rd_en,
    input  wire [9:0] rd_addr,
    output reg  [5:0] rd_data,
    output reg        rd_valid,
    input  wire       wr_en,
    input  wire [9:0] wr_addr,
    input  wire [5:0] wr_data
);

    reg [5:0] memory [0:1023];

    always @(posedge clk) begin
        if (wr_en)
            memory[wr_addr] <= wr_data;
    end

    always @(posedge clk) begin
        if (rst) begin
            rd_data  <= 6'd0;
            rd_valid <= 1'b0;
        end else begin
            rd_valid <= rd_en;
            if (rd_en)
                rd_data <= memory[rd_addr];
        end
    end

endmodule
