`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: anlgoic
// Author: 	xg 
// description:  top module
//////////////////////////////////////////////////////////////////////////////////

`define DEBUG

`include "../user_source/hdl_source/include/global_def.v"

module sdram(
    `ifdef SIMULATION
	output					SDRAM_CLK,
	output					SDR_CKE,
	output					SDR_RAS,
	output					SDR_CAS,
	output					SDR_WE,
	output	[`BA_WIDTH-1:0]	SDR_BA,
	output	[`ROW_WIDTH-1:0]SDR_ADDR,
	output	[`DM_WIDTH-1:0]	SDR_DM,
	inout	[`DATA_WIDTH-1:0]	SDR_DQ,	
	`endif
    input   					Clk,
    input						Clk_sft,
    input						Rst,
    input						App_ref_allow,
    input						frame_tick,

    output 						Sdr_init_done,
    output						Sdr_init_ref_vld,
    output						Sdr_busy,
    
    input						App_wr_en,
	input [`ADDR_WIDTH-1:0]		App_wr_addr,  	
	input [`DM_WIDTH-1:0]		App_wr_dm,
	input [`DATA_WIDTH-1:0]		App_wr_din,	//synthesis keep
    
    input 						App_rd_en,
	input [`ADDR_WIDTH-1:0]		App_rd_addr,
	output 						Sdr_rd_en,
	output [`DATA_WIDTH-1:0]	Sdr_rd_dout	//synthesis keep
    
    
    
);
`ifndef SIMULATION
wire  			SDRAM_CLK;
wire 			SDR_RAS;
wire  			SDR_CAS;
wire  			SDR_WE;
wire  [`BA_WIDTH-1:0]	SDR_BA; 
wire  [`ROW_WIDTH-1:0]	SDR_ADDR;
wire  [`DATA_WIDTH-1:0]	SDR_DQ ;
wire  [`DM_WIDTH-1:0]	SDR_DM; 
`endif

// 任务21：帧消隐离散刷新脉冲串（声明须在例化引用之前）
localparam integer REF_PULSE_PERIOD = 16;      // 脉冲周期，128ns@125MHz（>tRFC~70ns）
localparam integer REF_PULSE_WIDTH  = 2;       // 每个脉冲高电平拍数
localparam integer REF_PULSE_NUM    = 600;     // 每帧刷新请求条数（需求约538，留裕量）
localparam integer REF_WIN_END      = REF_PULSE_NUM*REF_PULSE_PERIOD; // 9600拍=76.8us
localparam integer VB_GUARD         = 12500;   // 起点保护：先让读独占填满rfifo，100us
localparam integer VB_ALL_END       = VB_GUARD+REF_WIN_END; // 22100拍=176.8us
reg        app_ref_req_r;
reg        app_allow_meta, app_allow_sync;
reg [1:0]  ft_sync;
reg        ft_prev;
reg [14:0] vblank_cnt;
reg        vblank_burst;
wire       ft_rise;

sdr_as_ram  #( .self_refresh_open(1'b1))
	u2_ram( 
		.Sdr_clk(Clk),
		.Sdr_clk_sft(Clk_sft),
		.Rst(Rst),
			  			  
		.Sdr_init_done(Sdr_init_done),
		.Sdr_init_ref_vld(Sdr_init_ref_vld),
		.Sdr_busy(Sdr_busy),
		
		.App_ref_req(app_ref_req_r),
		
        .App_wr_en(App_wr_en), 
        .App_wr_addr(App_wr_addr),  	
		.App_wr_dm(App_wr_dm),
		.App_wr_din(App_wr_din),

		.App_rd_en(App_rd_en),
		.App_rd_addr(App_rd_addr),
		.Sdr_rd_en	(Sdr_rd_en),
		.Sdr_rd_dout(Sdr_rd_dout),
	
		.SDRAM_CLK(SDRAM_CLK),
		.SDR_RAS(SDR_RAS),
		.SDR_CAS(SDR_CAS),
		.SDR_WE(SDR_WE),
		.SDR_BA(SDR_BA),
		.SDR_ADDR(SDR_ADDR),
		.SDR_DM(SDR_DM),
		.SDR_DQ(SDR_DQ)	
	);


assign SDR_CKE=1'b1;

// ---- 任务21：帧消隐突发刷新 ----
// App_ref_allow(all_resident) 与 frame_tick 同步到 125MHz 域
always @(posedge Clk or posedge Rst) begin
    if (Rst) begin
        app_allow_meta <= 1'b0;
        app_allow_sync <= 1'b0;
        ft_sync        <= 2'b0;
        ft_prev        <= 1'b0;
    end else begin
        app_allow_meta <= App_ref_allow;
        app_allow_sync <= app_allow_meta;
        ft_sync        <= {ft_sync[0], frame_tick};
        ft_prev        <= ft_sync[1];
    end
end
assign ft_rise = ft_sync[1] & !ft_prev;

// 仅在 vblank 内、且全部常驻后发一串离散刷新脉冲；有效显示行内不发
always @(posedge Clk or posedge Rst) begin
    if (Rst) begin
        vblank_burst    <= 1'b0;
        vblank_cnt      <= 14'd0;
        app_ref_req_r   <= 1'b0;
    end else if (!Sdr_init_done || !app_allow_sync) begin
        vblank_burst    <= 1'b0;
        vblank_cnt      <= 14'd0;
        app_ref_req_r   <= 1'b0;
    end else begin
        if (ft_rise && !vblank_burst) begin
            vblank_burst <= 1'b1;
            vblank_cnt   <= 14'd0;
        end else if (vblank_burst) begin
            // GUARD：先让读独占填满rfifo；GUARD后在读空闲段发脉冲串
            app_ref_req_r <= (vblank_cnt >= VB_GUARD) && (vblank_cnt < VB_ALL_END) &&
                             (((vblank_cnt - VB_GUARD) % REF_PULSE_PERIOD) < REF_PULSE_WIDTH);
            if (vblank_cnt == VB_ALL_END-1) begin
                vblank_burst    <= 1'b0;
                app_ref_req_r   <= 1'b0;
            end else begin
                vblank_cnt <= vblank_cnt + 1'b1;
            end
        end else begin
            app_ref_req_r <= 1'b0;
        end
    end
end

//`ifndef SIMULATION
	EG_PHY_SDRAM_2M_32 sdram(
		.clk(SDRAM_CLK),
		.ras_n(SDR_RAS),
		.cas_n(SDR_CAS),
		.we_n(SDR_WE),
		.addr(SDR_ADDR[10:0]),
		.ba(SDR_BA),
		.dq(SDR_DQ),
		.cs_n(1'b0),
		.dm0(SDR_DM[0]),
		.dm1(SDR_DM[1]),
		.dm2(SDR_DM[2]),
		.dm3(SDR_DM[3]),
		.cke(1'b1)
		);
//`endif

endmodule 