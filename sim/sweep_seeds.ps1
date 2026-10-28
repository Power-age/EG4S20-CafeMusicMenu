$ErrorActionPreference = 'Continue'
$phy = 'D:\AAA_University\Anlu\Project\src\td_project\HDMI1.4b_Transmitter_v1.0_Runs\phy_1'
$bak = 'D:\AAA_University\Anlu\Project\sim\backups\seed_sweep_v2'
New-Item -ItemType Directory -Force -Path $bak | Out-Null
$td = 'D:/TD5.6.2/bin/td_commands_prompt.exe'
$tcl = 'D:/TD5.6.2/doc/scripts/DefaultFlow.tcl'
$seeds = 13,17,3,19,23
$rows = @()

foreach ($s in $seeds) {
    Write-Output "=== seed $s ==="
    Push-Location $phy
    (Get-Content settings.cfg) -replace 'place seed \d+', "place seed $s" | Set-Content settings.cfg -Encoding ascii
    Get-ChildItem -File | Where-Object { $_.Name -like '*.db' -or $_.Name -like '*.timing' } | Remove-Item -Force -ErrorAction SilentlyContinue
    & $td $tcl > $null 2>&1
    $rpt = Join-Path $phy 'HDMI1.4b_Transmitter_v1.0_pr.timing'
    if (Test-Path $rpt) {
        $lines = Select-String -Path $rpt -Pattern 'Max\s*:\s+SWNS\s+(-?[\d.]+)' | ForEach-Object { [double]$_.Matches[0].Groups[1].Value }
        if ($lines.Count -ge 3) {
            $sd = $lines[0]; $vd = $lines[1]; $ex = $lines[2]
            $score = [Math]::Min([Math]::Min($sd, $vd), $ex)
            "  sd=$sd video=$vd ext=$ex score=$score"
            $rows += [pscustomobject]@{ Seed=$s; Sd=$sd; Video=$vd; Ext=$ex; Score=$score }
            Copy-Item 'HDMI1.4b_Transmitter_v1.0.bit' (Join-Path $bak ("seed$s.bit")) -Force
        } else { "  parse: only $($lines.Count) lines" }
    } else { "  no report (route failed?)" }
    Pop-Location
}

Write-Output ''
Write-Output '=== 汇总 ==='
$rows | Sort-Object Score -Descending | Format-Table -AutoSize
if ($rows.Count -gt 0) {
    $best = ($rows | Sort-Object Score -Descending)[0]
    Write-Output ("BEST seed {0}  sd={1} video={2} ext={3} score={4}" -f $best.Seed, $best.Sd, $best.Video, $best.Ext, $best.Score)
}
