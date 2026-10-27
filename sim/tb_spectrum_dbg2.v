`timescale 1ns/1ps
module tb_spectrum_dbg2;
    localparam integer N_SAMP = 38400;

    reg         clk;
    reg         rst;
    reg         sample_valid;
    reg  [23:0] sample_r;
    wire [239:0] bands;
    wire        bands_valid;

    reg  [15:0] stim [0:N_SAMP-1];
    integer     fd;
    integer     idx;
    integer     k;
    reg  [31:0] acc;
    integer     blk;

    spectrum_engine u_dut (
        .clk(clk), .rst(rst), .sample_valid(sample_valid), .sample_r(sample_r),
        .frame_pulse(1'b0), .bands(bands), .bands_valid(bands_valid)
    );

    initial clk = 1'b0;
    always #19.861 clk = ~clk;

    initial begin
        $readmemh("spec_stim2.mem", stim);
        fd  = $fopen("spec_dbg2_out.txt", "w");
        blk = 0;
        $fwrite(fd, "# blk i h_rd sm1 sm2 sm_val w_idx pk\n");
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
        if (!rst && (u_dut.state == 2'd2)) begin
            $fwrite(fd, "%0d %0d %0d %0d %0d %0d %0d %0d\n",
                    blk, u_dut.upd_bin, u_dut.h_rd, u_dut.sm1, u_dut.sm2,
                    u_dut.sm_val, u_dut.w_idx, u_dut.bands[6*u_dut.w_idx +: 6]);
            if (u_dut.upd_bin == 6'd41) blk = blk + 1;
        end
    end

    always @(posedge clk) begin
        if (!rst && bands_valid) begin
            $fwrite(fd, "OUT %0d", blk);
            for (k = 0; k < 40; k = k + 1)
                $fwrite(fd, " %0d", bands[6*k +: 6]);
            $fwrite(fd, "\n");
        end
    end

    initial begin
        wait (idx >= N_SAMP - 1);
        repeat (40000) @(posedge clk);
        $fclose(fd);
        $display("DBG2_DONE blocks=%0d", blk);
        $finish;
    end
endmodule
