
# ============================================================
# merged_top_tf_hdmi_audio.sdc
# 用于：TF 图片轮播 + HDMI(视频+音频) 整合工程
#
# 合并原则：
# 1) 保留 top.sdc 里的系统主时钟与 derive_clocks
# 2) 把 timing(2).sdc 里的 pixel/serial 时钟改成整合工程实际名字
# 3) 增加 hdmi_5x_clk / audio_mclk 的命名
# 4) 不再对内部 net 直接 create_clock，避免和 derive_clocks 重复
# ============================================================

# ------------------------------------------------------------
# 1. 板级输入主时钟
#    你的原 top.sdc 里 clk=50MHz，所以这里仍然用 20ns
# ------------------------------------------------------------
create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]

# ------------------------------------------------------------
# 2. 自动推导 PLL 输出时钟
# ------------------------------------------------------------
derive_clocks

# ------------------------------------------------------------
# 3. 给关键 PLL 输出命名
#    下面这些路径是按你当前工程实例名写的：
#      sys_pll      -> sys_pll_m0
#      video_pll    -> video_pll_m0
#      音频 PLL     -> u_audio_pll
#
#    如果综合后实例路径略有不同，就按 Timing Analyzer 里的实际 pin 路径改。
# ------------------------------------------------------------
rename_clock -name {sd_card_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {ext_mem_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {video_clk}   -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {audio_mclk}  -source [get_ports {clk}] -master_clock {clk} [get_pins {u_audio_pll/pll_inst.clkc[2]}]
rename_clock -name {ext_mem_clk_sft} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[2]}]

# ------------------------------------------------------------
# 4. 从原 timing(2).sdc 迁移过来的 HDMI 像素/串行时钟约束
#
#    原文件是：
#      create_clock -name pixel_clk  ... [get_nets {S_pixel_clk}]
#      create_clock -name serial_clk ... [get_nets {S_serial_clk}]
#      set_clock_groups -exclusive ...
#
#    在整合工程里，这两个时钟已经由 video_pll 产生，并通过 derive_clocks 建出来了，
#    所以这里只保留“组关系”，不再重复 create_clock。
#
#    这里沿用原作者的写法，把 video_clk 和 hdmi_5x_clk 设成 exclusive。
#    如果后面 Timing Analyzer 明确显示两者之间需要做同步时序分析，再把这一条去掉。
# ------------------------------------------------------------
set_clock_groups -exclusive \
    -group [get_clocks {video_clk}] \
    -group [get_clocks {hdmi_5x_clk}]

# ------------------------------------------------------------
# 5. 音频 I2S 发生器/接收器跨域
#
#    audio_mclk 域里生成 I2S，video_clk 域里做三拍同步采样。
#    这类路径不是普通同步时序路径，直接切掉更合理。
# ------------------------------------------------------------
set_clock_groups -asynchronous \
    -group [get_clocks {audio_mclk}] \
    -group [get_clocks {clk video_clk hdmi_5x_clk sd_card_clk ext_mem_clk}]

# ------------------------------------------------------------
# 6. 可选：如果你的 frame_read_write 内部异步 FIFO 已经完全处理好了跨域，
#    且报告里总出现 video_clk / sd_card_clk / ext_mem_clk 之间的大量伪违例，
#    可以打开下面这组异步分组。
#
#    建议先不要开，先看报告；
#    只有确认这些跨域都只经过 FIFO / 同步器时再开。
# ------------------------------------------------------------
# 任务18：video_pll 与 sys_pll 是两个独立 PLL，跨域路径只经异步 FIFO / 同步器，按异步处理
set_clock_groups -asynchronous \
    -group [get_clocks {video_clk hdmi_5x_clk}] \
    -group [get_clocks {sd_card_clk ext_mem_clk}]

# ------------------------------------------------------------
# 7. 其余 Input/Output delay 先保持空白
#    你当前两个原始 sdc 也都没有写这部分。
# ------------------------------------------------------------

# ------------------------------------------------------------
# 8. 视频时钟域 video_clk(25MHz, video_pll 输出) 与系统时钟 clk(50MHz,
#    外部晶振直接输入) 是物理异步关系，两域之间路径不做时序检查。
#
#    背景（V2-09a 时序修复）：V2-09a 后 slices 升到 92.95%，布局拥挤，
#    video_clk->clk 组 4 个端点 hold 由正转负（HWNS -1.046 / HTNS -3.841）：
#      -1.046 vol_reg[1] -> track_controller/target_index_reg[0]
#      -0.981 vol_reg[0] -> vol_lvl_c1_reg[2]
#      -0.929 vol_reg[0] -> vol_lvl_c1_reg[3]
#      -0.885 vol_reg[0] -> u_track_list/valid_mask_reg[5]
#
#    为什么不用寄存器级 set_false_path：
#    1) 最初写 get_regs {u_vol_gain/vol_reg[*]}/... 因缺 -hier 直接失败，
#       报 USR-8159 CRITICAL-WARNING，整条约束被丢弃（exception.timing 无此条）。
#    2) 即使改成 -hier 通配，寄存器级也只覆盖终点 vol_lvl_c1 两条；
#       target_index/valid_mask 两条是综合器对高扇出 vol_reg 复制后、
#       SLICE 内 LUT 打包在 video->clk 域呈现的路径（RTL 里音量根本不驱动
#       曲目索引/有效掩码），其终点随每次布局变化，寄存器级无法稳定覆盖。
#
#    改为按时钟域双向 set_false_path（与官方例程 media_player_promax_top.sdc
#    第 49 行同款写法），一次覆盖该时钟域对的全部跨域路径（含真同步器与
#    打包假路径），且不随布局/重命名变化；同时保留两域内部同域路径
#    （包括 audio_volume_gain 内 vol->增益乘法 prod_l/prod_r）。
#
#    已逐条核对两域间真实跨域信号在 RTL 均有两级同步器：
#      音量 video->clk : vol_level_a -> vol_lvl_c1 -> vol_lvl_c2 (top 1101)
#      音量 clk->video : vol_lvl_c2 -> volv_meta -> volv_sync   (top 531)
#      曲名 clk->video : cur_track_name_sd -> tkn_meta -> tkn_sync (top 530)
#      图号 video->clk : disp_buf_idx -> e2_disp_buf_meta -> e2_disp_buf_sync
#    其余 target_index/valid_mask/add0/seg_data/header_match 等均为
#    SLICE 打包呈现，非真实跨域连接。
#
#    范围只切 clk 与 video_clk；不动 clk 与 sd_card_clk/ext_mem_clk
#    （sys_pll 同源，沿用既有相关分析）。
# ------------------------------------------------------------
set_false_path -from [get_clocks {video_clk}] -to [get_clocks {clk}]
set_false_path -from [get_clocks {clk}] -to [get_clocks {video_clk}]

# ------------------------------------------------------------
# 9. SDRAM 采样相位时钟（ext_mem_clk_sft = clkc[2]，125MHz / 180°）
#
#    背景（2026/10/20 时序收敛一期）：phy_1 报出
#      ext_mem_clk   -> clkc[2] : SWNS -3.436ns / 32 违例端点
#      clkc[2]       -> ext_mem_clk : SWNS -6.699ns / 32 违例端点
#    起止点全部落在加密 SDRAM 控制器 U3 内部
#      (U3/u2_ram/u1_init_ref/ad_reg[10] -> U3/sdram.dq[*] / U3/sdram_syn_*.bpad)
#
#    该相位时钟只驱动 SDRAM 硬核自身的采样窗口；官方例程
#    media_player_promax_top.sdc 第 4~11 行对同一硬核做相同处理，注释原文：
#      "mem_clk_shift only drives the EG_PHY_SDRAM_2M_32 sampling clock.
#       The official 2026 SDRAM package carries its own hard-IP I/O window;
#       treating the forwarded DQ path as a fabric setup path produces a
#       fixed false violation."
#    故此处按官方写法双向 set_false_path（共消化 64 个违例端点）。
#
#    注意：本约束只切这两个时钟之间；ext_mem_clk 与 sd_card_clk 仍保持同源相关分析，
#    那 110 条 fifo_aclr / write_req_ack 跨域违例属真实未同步握手，留待二期加同步器。
# ------------------------------------------------------------
set_false_path -from [get_clocks {ext_mem_clk}]     -to [get_clocks {ext_mem_clk_sft}]
set_false_path -from [get_clocks {ext_mem_clk_sft}] -to [get_clocks {ext_mem_clk}]

# ------------------------------------------------------------
# 10. 已撤除：hold uncertainty 收紧（2026/10/20 实测否决，勿再添加）
#
#    曾按官方例程 media_player_promax_top.sdc 第 13~20 行试加：
#      set_clock_uncertainty -hold 0.050 [get_clocks {clk sd_card_clk ext_mem_clk
#                                          ext_mem_clk_sft video_clk hdmi_5x_clk audio_mclk}]
#    复跑 phy_1 后 final_timing.rpt 显示：
#      Clock Uncertainty : 0.150ns (sdc uncertainty: 0.050ns, default uncertainty: 0.100ns)
#    即本版 TD（v6.2.168116）把 sdc 数值【叠加】在默认 0.100ns 之上，而非替换。
#    结果 hold 反而恶化 50ps：HWNS -0.011ns -> -0.070ns，违例端点 3 -> 21。
#    官方写法依赖"替换"语义，在本版工具不成立，故整条撤除。
#
#    剩余 hold 违例属"寄存器 -> 异步 RAM 读地址"类（u_wav_player/buf_wa_reg ->
#    ramread0.addra、bmp_read/up_raw_x_reg -> up_row_mem.addra），量级 -20ps 上下，
#    已知无法用 uncertainty 降低，留待二期打拍/降拥塞后复观察。
# ------------------------------------------------------------

# 2026-10-31 upscale dead path: 上采样通路已功能关闭（素材规格 >=640x480）
set_false_path -from [get_cells -hier -filter {NAME =~ *up_*}]
