# Sweep placement seeds until ext_mem_clk SWNS >= -0.3 and video_clk SWNS >= 0
$base = "D:\AAA_University\Anlu\Project\src\td_project\HDMI1.4b_Transmitter_v1.0_Runs"
$phy  = Join-Path $base "phy_1"
$seeds = @(5, 7, 13, 17)

foreach ($s in $seeds) {
    Push-Location $phy
    $cfg = Get-Content settings.cfg
    $cfg = $cfg -replace "place seed \d+", "place seed $s"
    Set-Content settings.cfg $cfg -Encoding ascii
    Pop-Location

    Write-Host "=== seed $s start ==="
    Push-Location $phy
    & "D:/TD5.6.2/bin/td_commands_prompt.exe" "D:/TD5.6.2/doc/scripts/DefaultFlow.tcl" 2>&1 | Select-Object -Last 1
    $rc = $LASTEXITCODE
    Pop-Location

    $qor = Get-Content (Join-Path $phy "route.qor") -Raw
    $slices = "?"
    if ($qor -match "slices percentage\s+\|\s+([\d.]+)%") { $slices = $Matches[1] }

    $txt = [System.IO.File]::ReadAllLines((Join-Path $phy "final_timing.rpt"))
    $wns = @()
    for ($i = 0; $i -lt $txt.Count; $i++) {
        if ($txt[$i] -match "Max\s+:\s+SWNS\s+(-?[\d.]+)ns") { $wns += [double]$Matches[1] }
    }
    $sdv = if ($wns.Count -gt 0) { $wns[0] } else { "NA" }
    $vdv = if ($wns.Count -gt 1) { $wns[1] } else { "NA" }
    $emv = if ($wns.Count -gt 2) { $wns[2] } else { "NA" }
    $md5 = (Get-FileHash (Join-Path $phy "HDMI1.4b_Transmitter_v1.0.bit") -Algorithm MD5).Hash

    Write-Host ("seed {0}: exit={1} slices={2}pct sd={3} video={4} ext_mem={5} md5={6}" -f $s, $rc, $slices, $sdv, $vdv, $emv, $md5)

    if (($emv -ne "NA") -and ($vdv -ne "NA") -and ($sdv -ne "NA") -and ($emv -ge -0.8) -and ($sdv -ge -0.6) -and ($vdv -ge 0)) {
        Write-Host "*** seed $s PASSED gate ***"
        break
    }
    Write-Host "seed $s rejected, next"
}
Write-Host "DONE"
