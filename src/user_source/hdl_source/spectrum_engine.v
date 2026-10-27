// 音频频谱引擎（V4）：1024 点分块 DFT，24 个对数频段
module spectrum_engine (
    input  wire         clk,
    input  wire         rst,
    input  wire         sample_valid,
    input  wire [23:0]  sample_r,
    input  wire         frame_pulse,
    input  wire         plain,
    output reg  [239:0] bands,
    output reg          bands_valid
);
    localparam [1:0] S_CAP  = 2'd0;
    localparam [1:0] S_CALC = 2'd1;
    localparam [1:0] S_UPD  = 2'd2;
    localparam integer N = 1024;

    reg [1:0]  state;
    reg [9:0]  wr_addr;
    reg [5:0]  bin;
    reg [9:0]  n;
    reg [9:0]  phase;
    reg [5:0]  band_h  [0:39];
    reg [5:0]  upd_bin;
    reg [1:0]  decay_div;
    reg signed [31:0] acc_i;
    reg signed [31:0] acc_q;

    wire [15:0] cos_d, sin_d, smp_d;
    wire [9:0]  tab_addr  = phase;
    wire [9:0]  samp_addr = (state == S_CAP) ? wr_addr : n;
    wire        samp_we   = (state == S_CAP) && sample_valid;
    wire [15:0] samp_din  = sample_r[23:8];

`ifdef SPECTRUM_SIM
    reg [15:0] cos_mem [0:1023];
    reg [15:0] sin_mem [0:1023];
    reg [15:0] smp_mem [0:1023];
    reg [15:0] cos_q, sin_q, smp_q;
    integer zi;
    initial begin
        $readmemh("spec_cos.mem", cos_mem);
        $readmemh("spec_sin.mem", sin_mem);
        for (zi = 0; zi < 1024; zi = zi + 1) smp_mem[zi] = 16'd0;
    end
    always @(posedge clk) begin
        if (samp_we) smp_mem[samp_addr] <= samp_din;
        cos_q <= cos_mem[tab_addr];
        sin_q <= sin_mem[tab_addr];
        smp_q <= smp_mem[samp_addr];
    end
    assign cos_d = cos_q;
    assign sin_d = sin_q;
    assign smp_d = smp_q;
`else

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(16), .ADDR_WIDTH_A(10), .DATA_DEPTH_A(1024),
        .DATA_WIDTH_B(16), .ADDR_WIDTH_B(10), .DATA_DEPTH_B(1024),
        .MODE("SP"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("ON"), .INIT_FILE("../../user_source/hdl_source/spec_cos.mif"),
        .FILL_ALL("NONE"), .IMPLEMENT("9K")
    ) u_cos (
        .dia(16'd0), .addra(tab_addr), .cea(1'b1), .ocea(1'b0),
        .clka(clk), .wea(1'b0), .rsta(1'b0), .bea(1'b0),
        .dib(16'd0), .addrb(10'd0), .ceb(1'b0), .oceb(1'b0),
        .clkb(clk), .web(1'b0), .rstb(1'b0), .beb(1'b0),
        .doa(cos_d), .dob()
    );

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(16), .ADDR_WIDTH_A(10), .DATA_DEPTH_A(1024),
        .DATA_WIDTH_B(16), .ADDR_WIDTH_B(10), .DATA_DEPTH_B(1024),
        .MODE("SP"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("ON"), .INIT_FILE("../../user_source/hdl_source/spec_sin.mif"),
        .FILL_ALL("NONE"), .IMPLEMENT("9K")
    ) u_sin (
        .dia(16'd0), .addra(tab_addr), .cea(1'b1), .ocea(1'b0),
        .clka(clk), .wea(1'b0), .rsta(1'b0), .bea(1'b0),
        .dib(16'd0), .addrb(10'd0), .ceb(1'b0), .oceb(1'b0),
        .clkb(clk), .web(1'b0), .rstb(1'b0), .beb(1'b0),
        .doa(sin_d), .dob()
    );

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(16), .ADDR_WIDTH_A(10), .DATA_DEPTH_A(1024),
        .DATA_WIDTH_B(16), .ADDR_WIDTH_B(10), .DATA_DEPTH_B(1024),
        .MODE("DP"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("ON"), .INIT_FILE("../../user_source/hdl_source/spec_samp_zero.mif"),
        .FILL_ALL("NONE"), .IMPLEMENT("9K")
    ) u_samp (
        .dia(samp_din), .addra(samp_addr), .cea(samp_we), .ocea(1'b0),
        .clka(clk), .wea(samp_we), .rsta(1'b0), .bea(1'b0),
        .dib(16'd0), .addrb(samp_addr), .ceb(1'b1), .oceb(1'b0),
        .clkb(clk), .web(1'b0), .rstb(1'b0), .beb(1'b0),
        .doa(), .dob(smp_d)
    );
`endif

    reg [8:0] kbin;
    always @(*) begin
        case (bin)
            6'd 0: kbin = 9'd  1;
            6'd 1: kbin = 9'd  2;
            6'd 2: kbin = 9'd  3;
            6'd 3: kbin = 9'd  4;
            6'd 4: kbin = 9'd  5;
            6'd 5: kbin = 9'd  6;
            6'd 6: kbin = 9'd  7;
            6'd 7: kbin = 9'd  8;
            6'd 8: kbin = 9'd  9;
            6'd 9: kbin = 9'd 10;
            6'd10: kbin = 9'd 11;
            6'd11: kbin = 9'd 12;
            6'd12: kbin = 9'd 13;
            6'd13: kbin = 9'd 14;
            6'd14: kbin = 9'd 15;
            6'd15: kbin = 9'd 16;
            6'd16: kbin = 9'd 17;
            6'd17: kbin = 9'd 18;
            6'd18: kbin = 9'd 19;
            6'd19: kbin = 9'd 20;
            6'd20: kbin = 9'd 23;
            6'd21: kbin = 9'd 26;
            6'd22: kbin = 9'd 29;
            6'd23: kbin = 9'd 33;
            6'd24: kbin = 9'd 38;
            6'd25: kbin = 9'd 43;
            6'd26: kbin = 9'd 49;
            6'd27: kbin = 9'd 55;
            6'd28: kbin = 9'd 63;
            6'd29: kbin = 9'd 72;
            6'd30: kbin = 9'd 81;
            6'd31: kbin = 9'd 92;
            6'd32: kbin = 9'd105;
            6'd33: kbin = 9'd119;
            6'd34: kbin = 9'd135;
            6'd35: kbin = 9'd154;
            6'd36: kbin = 9'd175;
            6'd37: kbin = 9'd198;
            6'd38: kbin = 9'd225;
            6'd39: kbin = 9'd256;
            default: kbin = 9'd256;
        endcase
    end

    wire signed [15:0] smp_s  = smp_d;
    wire signed [47:0] prod_i = smp_s * $signed(cos_d);
    wire signed [47:0] prod_q = smp_s * $signed(sin_d);
    wire signed [31:0] pi_sh  = prod_i[46:15];
    wire signed [31:0] pq_sh  = prod_q[46:15];

    wire [31:0] abs_i = acc_i[31] ? (~acc_i + 32'd1) : acc_i;
    wire [31:0] abs_q = acc_q[31] ? (~acc_q + 32'd1) : acc_q;
    wire [31:0] mag_v = abs_i + abs_q;      // L1 范数，比 max() 高约 3dB

    reg [4:0] msb;
    integer bi;
    always @(*) begin
        msb = 5'd0;
        for (bi = 0; bi < 32; bi = bi + 1)
            if (mag_v[bi]) msb = bi[4:0];
    end
    wire [4:0] fbase = (msb >= 5'd2) ? (msb - 5'd1) : 5'd1;
    wire [1:0] frac  = mag_v[fbase -: 2];
    wire [6:0] fine  = {msb, frac};

    localparam [4:0] GATE_MSB  = 5'd8;
    wire abs_ok = (msb >= GATE_MSB);
    wire signed [7:0]  gdiff = $signed({1'b0, fine}) - 8'sd88;
    wire signed [10:0] gd2   = {{3{gdiff[7]}}, gdiff} <<< 1;
    wire signed [10:0] gmap  = 11'sd52 + gd2;
    wire [5:0] h_agc = (gmap < 11'sd0)  ? 6'd0 :
                       (gmap > 11'sd63) ? 6'd63 : gmap[5:0];

    // 噪声门：低于 3 直接归零
    wire [5:0]  mag_h6 = (abs_ok && (h_agc >= 6'd3)) ? h_agc : 6'd0;

    reg  [5:0]  sm1, sm2;
    wire [5:0]  h_rd   = (upd_bin <= 6'd39) ? band_h[upd_bin] : sm1;
    wire [7:0]  sm_sum = {2'b00, sm2} + {1'b0, sm1, 1'b0} + {2'b00, h_rd};
    wire [5:0]  sm_val = sm_sum[7:2];
    wire [5:0]  w_idx  = ((upd_bin == 6'd0) || (upd_bin > 6'd40)) ? 6'd0 : (upd_bin - 6'd1);

    wire signed [7:0] sm_s   = $signed({1'b0, sm_val});
    wire signed [7:0] sm_d32 = sm_s - 8'sd32;
    wire signed [9:0] gm_h   = 10'sd32 + sm_d32 + (sm_d32 >>> 1);
    wire [5:0] gm_val  = (gm_h < 10'sd0) ? 6'd0 : (gm_h > 10'sd63) ? 6'd63 : gm_h[5:0];
    wire [5:0] gm_gate = (gm_val < 6'd3) ? 6'd0 : gm_val;


    integer b;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_CAP; wr_addr <= 10'd0; bin <= 6'd0; n <= 10'd0; phase <= 10'd0;
            acc_i <= 32'sd0; acc_q <= 32'sd0; bands <= 144'd0; bands_valid <= 1'b0; upd_bin <= 6'd0;
            sm1 <= 6'd0; sm2 <= 6'd0;
            for (b = 0; b < 40; b = b + 1) begin
                band_h[b] <= 6'd0;
            end
        end else begin
            bands_valid <= 1'b0;
            case (state)
                S_CAP: begin
                    if (sample_valid) begin
                        if (wr_addr == N - 1) begin
                            wr_addr <= 10'd0; bin <= 6'd0; n <= 10'd0; phase <= 10'd0;
                            acc_i <= 32'sd0; acc_q <= 32'sd0; state <= S_CALC;
                        end else wr_addr <= wr_addr + 10'd1;
                    end
                end
                S_CALC: begin
                    acc_i <= acc_i + pi_sh;
                    acc_q <= acc_q + pq_sh;
                    phase <= phase + kbin;
                    if (n == N - 1) begin
                        n <= 10'd0;

                        if (bin == 6'd39) begin
                            band_h[39] <= mag_h6; upd_bin <= 6'd0; state <= S_UPD;
                        end else begin
                            band_h[bin] <= mag_h6; bin <= bin + 6'd1;
                        end
                    end else n <= n + 10'd1;
                end
                S_UPD: begin
                    sm1 <= h_rd;
                    sm2 <= (upd_bin == 6'd0) ? h_rd : sm1;
                    if (upd_bin != 6'd0 && upd_bin <= 6'd40) begin
                        if (plain)
                            bands[6*w_idx +: 6] <= ({2'b00, bands[6*w_idx +: 6]}
                                                  + {2'b00, bands[6*w_idx +: 6]}
                                                  + {2'b00, bands[6*w_idx +: 6]}
                                                  + {2'b00, gm_gate} + 8'd2) >> 2;
                        else if (bands[6*w_idx +: 6] > gm_gate)
                            bands[6*w_idx +: 6] <= (bands[6*w_idx +: 6] > 6'd1) ? (bands[6*w_idx +: 6] - 6'd1) : 6'd0;
                        else
                            bands[6*w_idx +: 6] <= gm_gate;
                    end
                    if (upd_bin == 6'd41) begin
                        bands_valid <= 1'b1; state <= S_CAP;
                    end else upd_bin <= upd_bin + 6'd1;
                end
                default: state <= S_CAP;
            endcase
        end
    end
endmodule