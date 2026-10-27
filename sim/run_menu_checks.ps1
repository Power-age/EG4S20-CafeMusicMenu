param([switch]$Baseline)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot
$hdlDir = Join-Path $projectRoot 'src/user_source/hdl_source'
$libDir = (Join-Path $PSScriptRoot 'work_menu_fix_20261023').Replace('\', '/')
$topText = Get-Content -LiteralPath (Join-Path $hdlDir 'top_tf_hdmi_audio.v') -Raw
$controller = [regex]::Match($topText, '(?s)menu_controller\s*#\(.*?\)\s*u_menu_controller\s*\(.*?\);').Value
$renderer = [regex]::Match($topText, '(?s)menu_renderer\s+u_menu_renderer\s*\(.*?\);').Value
$levels = [regex]::Match($topText, '(?s)always @\(posedge video_clk or posedge rst_all\) begin\s*if \(rst_all\) begin\s*brightness_level.*?\nend').Value
$legacyLevels = [bool]$levels
if (!$levels) { $levels = [regex]::Match($topText, 'assign brightness_level = m_bright;\s*assign contrast_level = m_contrast;').Value }
$gain = [regex]::Match($topText, '(?s)audio_volume_gain\s*#\(.*?\)\s*u_vol_gain\s*\(.*?\);').Value
$overlay = [regex]::Match($topText, '(?s)video_osd_overlay\s+u_video_osd_overlay\s*\(.*?\);').Value
if (!$controller -or !$renderer -or !$levels -or !$gain -or !$overlay) { throw 'Top-level extraction anchors missing' }
$controller = $controller.Replace('.CLOCK_MHZ  (25)', '.CLOCK_MHZ  (1)').Replace('.TIMEOUT_MS (15000)', '.TIMEOUT_MS (1000)')
$header = @'
module menu_top_extract(
    input video_clk, rst_all, k1_short_v, k2_short_v, key3_trig, sw_con0, sw_key_mode,
    input signed [23:0] hdmi_audio_left, hdmi_audio_right,
    input [23:0] vout_data_wave,
    output signed [23:0] vol_audio_l, vol_audio_r,
    output [3:0] vol_level_a,
    output [23:0] vout_data_pre,
    input osd_clr_done, menu_req_ready,
    output menu_panel_vis, menu_active, menu_editing, menu_redraw,
    output [2:0] menu_sel_row,
    output [3:0] m_volume, m_period,
    output [1:0] m_bright, m_contrast,
    output [2:0] m_trans,
    output m_auto, m_info,
    output menu_req_valid, menu_busy, menu_req_fill,
    output [6:0] menu_req_ascii, menu_req_y,
    output [7:0] menu_req_x,
    output [1:0] menu_req_type,
    output wire [1:0] brightness_level, contrast_level
);
wire vol_mode_v = ~sw_key_mode;
wire audio_valid = 1'b1;
wire display_valid_video = 1'b0;
wire wave_vs = 1'b0;
wire wave_de = 1'b1;
wire [3:0] state_code = 4'd0;
wire osd_auto_play_en = 1'b0;
wire param_default_en = 1'b0;
wire e2_transition_active = 1'b0;
wire [9:0] e2_transition_reveal_x = 10'd640;
wire [2:0] e2_fade_level = 3'd0;
'@
if ($legacyLevels) { $header = $header.Replace('output wire [1:0] brightness_level', 'output reg [1:0] brightness_level') }
if (!(Test-Path (Join-Path $libDir '_info'))) { & D:/Modelsim/Install/win64/vlib.exe $libDir }
$generated = Join-Path $libDir 'menu_top_extract.v'
[IO.File]::WriteAllText($generated, "$header`n$levels`n$controller`n$renderer`n$gain`n$overlay`nendmodule`n")
Push-Location $hdlDir
try {
    if (!(Test-Path (Join-Path $libDir '_info'))) { & D:/Modelsim/Install/win64/vlib.exe $libDir }
    $sources = @('menu_controller.v', 'menu_renderer.v', 'osd_renderer.v', 'font5x7_rom.v', 'font_rom.v', 'osd_buffer.v', 'osd_buffer_overlay.v', 'video_osd_overlay.v', 'SD/audio_volume_gain.v', $generated, (Join-Path $PSScriptRoot 'tb_menu_top.v'), (Join-Path $PSScriptRoot 'tb_menu_pipeline.v'), (Join-Path $PSScriptRoot 'tb_audio_volume.v'), (Join-Path $PSScriptRoot 'tb_menu_window.v'))
    & D:/Modelsim/Install/win64/vlog.exe -work $libDir '+define+FONT5X7_ROM_SIM+FONT_ROM_SIM+OSD_BUFFER_SIM' @sources
    if ($LASTEXITCODE -ne 0) { throw 'Menu compilation failed' }
    $tops = @('tb_menu_top', 'tb_menu_pipeline', 'tb_audio_volume', 'tb_menu_window')
    foreach ($testTop in $tops) {
        $testLog = Join-Path $libDir "$testTop.log"
        & D:/Modelsim/Install/win64/vsim.exe -c -quiet -lib $libDir $testTop -do 'onerror {quit -code 1}; onbreak {quit -code 1}; run -all; quit -code 0' -l $testLog
        if ($LASTEXITCODE -ne 0 -and !$Baseline) { throw "$testTop failed" }
        $testOutput = Get-Content -LiteralPath $testLog -Raw
        $passPattern = if ($testTop -eq 'tb_audio_volume') { 'AUDIO_VOLUME TEST PASS' } else { "PASS $testTop" }
        if (!$Baseline -and ($testOutput -match '(?im)^#\s*(?:\*\*\s*(?:Fatal|Error):|FAIL\b)|failures=[1-9][0-9]*' -or $testOutput -notmatch [regex]::Escape($passPattern))) {
            throw "$testTop failed log validation: $testLog"
        }
    }
} finally { Pop-Location }
