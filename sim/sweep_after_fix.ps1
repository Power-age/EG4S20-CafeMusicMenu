$ErrorActionPreference = 'Continue'
$phy = 'D:\AAA_University\Anlu\Project\src\td_project\HDMI1.4b_Transmitter_v1.0_Runs\phy_1'
$td  = 'D:/TD5.6.2/bin/td_commands_prompt.exe'
$tcl = 'D:/AAA_University/Anlu/Project/sim/DefaultFlow_hold.tcl'

$seeds = 3,7,13,17,23,29,31,37
$rows = @()

foreach ($s in $seeds) {
    Write-Output "=== seed $s ==="
    Push-Location $phy
    (Get-Content settings.cfg) -replace 'place seed \d+', "place seed $s" | Set-Content settings.cfg -Encoding ascii
    Get-ChildItem -File | Where-Object { $_.Name -like '*.db' -or $_.Name -like '*.timing' } | Remove-Item -Force -ErrorAction SilentlyContinue
    & $td $tcl > $null 2>&1
    $rpt = Join-Path $phy 'HDMI1.4b_Transmitter_v1.0_pr.timing'
    if (Test-Path $rpt) {
        $sns = Select-String -Path $rpt -Pattern 'Max\s*:\s+SWNS\s+(-?[\d.]+)' | ForEach-Object { [double]$_.Matches[0].Groups[1].Value }
        $hns = Select-String -Path $rpt -Pattern 'Min\s*:\s+HWNS\s+(-?[\d.]+)' | ForEach-Object { [double]$_.Matches[0].Groups[1].Value }
        $viol = (Select-String -Path $rpt -Pattern '(\d+) Viol Endpoints' | ForEach-Object { [int]$_.Matches[0].Groups[1].Value } | Measure-Object -Sum).Sum
        if ($sns.Count -ge 3) {
            $minAll = (($sns + $hns) | Measure-Object -Minimum).Minimum
            "  sd={0} video={1} ext={2}  minAll={3}  viol={4}" -f $sns[0], $sns[1], $sns[2], $minAll, $viol
            $rows += [pscustomobject]@{ Seed=$s; Sd=$sns[0]; Video=$sns[1]; Ext=$sns[2]; Min=$minAll; Viol=$viol }
        } else { '  parse failed' }
    } else { '  no report' }
    Pop-Location
}

Write-Output ''
Write-Output '=== summary (sorted by worst domain) ==='
$rows | Sort-Object Min -Descending | Format-Table -AutoSize
$allGood = $rows | Where-Object { $_.Viol -eq 0 } | Sort-Object Min -Descending | Select-Object -First 1
if ($allGood) { Write-Output ("PASS seed " + $allGood.Seed + "  min=" + $allGood.Min) } else { Write-Output 'no clean seed; keep sweeping or change RTL' }
