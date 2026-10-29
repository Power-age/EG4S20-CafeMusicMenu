param([int]$Seed = 17, [switch]$NoBuild, [int]$CaptureDelaySec = 3)
$ErrorActionPreference = "Stop"
$base = "D:\AAA_University\Anlu\Project\src\td_project\HDMI1.4b_Transmitter_v1.0_Runs"
$td   = "D:/TD5.6.2/bin/td_commands_prompt.exe"
$tcl  = "D:/AAA_University/Anlu/Project/sim/DefaultFlow_hold.tcl"   # 含 fix_hold
$bw   = "D:\TD5.6.2\bin\bw_commands_prompt.exe"
$burn = "D:/AAA_University/Anlu/Project/sim/burn_jtag.tcl"
$shot = "D:\AAA_University\Anlu\Project\sim\cam_capture.png"
$ffmpeg = "D:\Format\FormatFactory\ffmpeg.exe"

if (-not $NoBuild) {
    "=== SYN ==="
    Get-ChildItem "$base\syn_1" -Force -File | Where-Object { $_.Name -match "error" } | Remove-Item -Force
    Push-Location "$base\syn_1"
    & $td $tcl 2>&1 | Select-Object -Last 1
    Pop-Location
    $log = Get-ChildItem "$base\syn_1" -Filter "td_2026*.log" -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $bb = (Select-String -Path $log.FullName -Pattern "black box|unknown module" | Measure-Object).Count
    "black_box=$bb"
    if ($bb -ne 0) { Select-String -Path $log.FullName -Pattern "black box" | Select-Object -First 3 | ForEach-Object { "  " + $_.Line.Trim() } }
    Select-String -Path $log.FullName -Pattern "#registers|#luts|#slices" | ForEach-Object { "  " + $_.Line.Trim() }

    "=== PHY seed $Seed ==="
    Push-Location "$base\phy_1"
    (Get-Content settings.cfg) -replace "place seed \d+", "place seed $Seed" | Set-Content settings.cfg -Encoding ascii
    $phy_t0 = Get-Date
    & $td $tcl 2>&1 | Select-Object -Last 1
    Pop-Location

    $plog = Get-ChildItem "$base\phy_1" -Filter "td_2026*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $emb = (Select-String -Path $plog.FullName -Pattern "PHY-9013|exceeds the limit" | Measure-Object).Count
    $route_err = (Select-String -Path $plog.FullName -Pattern "RUN-8102|PHY-8023|Routing violations" | Measure-Object).Count
    $bit = Get-Item "$base\phy_1\HDMI1.4b_Transmitter_v1.0.bit"
    $fresh = ($bit.LastWriteTime -ge $phy_t0)
    "emb_violation=$emb route_err=$route_err bit_time=$($bit.LastWriteTime.ToString('HH:mm:ss')) fresh=$fresh"
    if ($emb -ne 0) {
        Select-String -Path $plog.FullName -Pattern "emb number" | Select-Object -First 1 | ForEach-Object { "  " + $_.Line.Trim() }
        "ABORT_EMB_LIMIT"
        exit 2
    }
    if ($route_err -ne 0) {
        Select-String -Path $plog.FullName -Pattern "RUN-8102|PHY-8023" | Select-Object -First 3 | ForEach-Object { "  " + $_.Line.Trim() }
        "ABORT_ROUTE_FAIL"
        exit 5
    }
    if (-not $fresh) { "ABORT_BIT_NOT_UPDATED"; exit 3 }

    Get-Content "$base\phy_1\route.qor" | Select-String -Pattern "slices percentage" | ForEach-Object { "  " + $_.Line.Trim() }
    $txt = [System.IO.File]::ReadAllLines("$base\phy_1\final_timing.rpt")
    $j = (0..($txt.Count - 1)) | Where-Object { $txt[$_] -match "Max\s+:\s+SWNS" }
    $names = @("sd_card", "video", "ext_mem")
    $wns = @()
    for ($n = 0; $n -lt 3; $n++) { if ($j.Count -gt $n) { "  {0,-8} {1}" -f $names[$n], (($txt[$j[$n]] -replace "\s+", " ").Trim()); if ($txt[$j[$n]] -match "SWNS\s+(-?[\d.]+)ns") { $wns += [double]$Matches[1] } } }
    if ($wns.Count -ge 3) {
        if (($wns[1] -lt 0) -or ($wns[2] -lt -0.8)) {
            "ABORT_TIMING video=$($wns[1]) ext_mem=$($wns[2]) (need video>=0, ext_mem>=-0.8)"
            exit 4
        }
    }
    Copy-Item "$base\phy_1\HDMI1.4b_Transmitter_v1.0.bit" "$base\best_result\" -Force
}

"=== BURN ==="
$md5 = (Get-FileHash "$base\best_result\HDMI1.4b_Transmitter_v1.0.bit" -Algorithm MD5).Hash
"md5=$md5"
& $bw $burn 2>&1 | Select-String "finish command .download|ERROR" | Select-Object -Last 1 | ForEach-Object { "  " + $_.Line }

"=== CAPTURE ==="
Start-Sleep -Seconds $CaptureDelaySec
& $ffmpeg -hide_banner -loglevel error -f dshow -i "video=USB Camera" -frames:v 1 -y $shot 2>&1 | Select-Object -Last 2
if (Test-Path $shot) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $dir = "D:\AAA_University\Anlu\Project\sim\shots"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Copy-Item $shot "$dir\shot_$stamp.png" -Force
    "shot=$dir\shot_$stamp.png"
} else { "CAPTURE_FAILED" }
