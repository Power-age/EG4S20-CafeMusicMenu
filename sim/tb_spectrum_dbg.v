`timescale 1ns/1ps
module tb_spectrum_dbg;
    localparam integer N_SAMP = 6000;

    reg         clk;
    reg         rst;
    reg         sample_valid;
    reg  [23:0] sample_r;
    wire [239:0] bands;
    wire        bands_valid;

    reg  [15:0] stim [0:N_SAMP-1];
    integer     fd;
    integer     idx;
    reg  [31:0] acc;
    integer     blk;

    spectrum_engine u_dut (
        .clk(clk), .rst(rst), .sample_valid(sample_valid), .sample_r(sample_r),
        .frame_pulse(1'b0), .bands(bands), .bands_valid(bands_valid)
    );

    initial clk = 1'b0;
    always #19.861 clk = ~clk;

    initial begin
        $readmemh("spec_stim.mem", stim);
        fd  = $fopen("spec_dbg_out.txt", "w");
        blk = 0;
        $fwrite(fd, "# blk bin msb frac fine gref h_agc\n");
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
                sample_r <= {stim[idx], 8'h00};
                if (idx < N_SAMP - 1) idx <= idx + 1;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst && (u_dut.state == 2'd1) && (u_dut.n == 10'd1023)) begin
            $fwrite(fd, "%0d %0d %0d %0d %0d %0d %0d\n",
                    blk, u_dut.bin, u_dut.msb, u_dut.frac, u_dut.fine,
                    u_dut.gref, u_dut.h_agc);
            if (u_dut.bin == 6'd39) blk = blk + 1;
        end
    end

    initial begin
        wait (idx >= N_SAMP - 1);
        repeat (60000) @(posedge clk);
        $fclose(fd);
        $display("DBG_DONE blocks=%0d", blk);
        $finish;
    end
endmodule
