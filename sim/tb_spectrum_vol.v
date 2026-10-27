`timescale 1ns/1ps
module tb_spectrum_vol;
    localparam integer N_BLK = 44;
    localparam integer N_SAMP = N_BLK * 1102;

    reg         clk;
    reg         rst;
    reg         sample_valid;
    reg  [23:0] sample_r;
    wire [239:0] bands;
    wire        bands_valid;

    reg  [15:0] stim [0:1023];
    integer     fd, idx, blk, k;
    reg  [31:0] acc;
    reg  [15:0] scaled;

    spectrum_engine u_dut (
        .clk(clk), .rst(rst), .sample_valid(sample_valid), .sample_r(sample_r),
        .frame_pulse(1'b0), .bands(bands), .bands_valid(bands_valid)
    );

    initial clk = 1'b0;
    always #19.861 clk = ~clk;

    initial begin
        $readmemh("spec_stim.mem", stim);
        fd = $fopen("spec_vol_out.txt", "w");
        blk = 0;
    end

    initial begin
        rst = 1'b1; sample_valid = 1'b0; sample_r = 24'd0; acc = 32'd0; idx = 0;
        repeat (10) @(posedge clk);
        rst <= 1'b0;
    end

    always @(posedge clk) begin
        if (rst) begin
            acc <= 32'd0; sample_valid <= 1'b0;
        end else begin
            acc <= acc + 32'd48000;
            sample_valid <= 1'b0;
            if (acc >= 32'd25127000) begin
                acc <= acc - 32'd25127000;
                sample_valid <= 1'b1;
                scaled <= (blk < 4) ? stim[idx[9:0]] : ($signed(stim[idx[9:0]]) >>> 4);
                sample_r <= {scaled, 8'h00};
                idx <= idx + 1;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst && bands_valid) begin
            $write("blk%0d %s bands:", blk, (blk < 4) ? "full  " : "-24dB ");
            for (k = 0; k < 40; k = k + 8)
                $write(" %0d", bands[6*k +: 6]);
            $write("   raw: %0d %0d\n", u_dut.band_h[8], u_dut.band_h[20]);
            blk = blk + 1;
            if (blk >= N_BLK) begin
                $fclose(fd);
                $display("VOL_DONE");
                $finish;
            end
        end
    end
endmodule
