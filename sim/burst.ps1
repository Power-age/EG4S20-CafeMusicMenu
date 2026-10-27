param([int]$Seconds = 12, [int]$Fps = 4, [int]$ScaleW = 0, [string]$Tag = "burst")
$ErrorActionPreference = "Stop"
$ffmpeg = "D:\Format\FormatFactory\ffmpeg.exe"
$stamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$dir    = "D:\AAA_University\Anlu\Project\sim\shots\${Tag}_$stamp"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$clip   = Join-Path $dir "clip.mp4"
& $ffmpeg -hide_banner -loglevel error -f dshow -rtbufsize 256M -i "video=USB Camera" -t $Seconds -y $clip
if (-not (Test-Path $clip)) { "RECORD_FAILED"; exit 1 }
$vf = "fps=$Fps"
if ($ScaleW -gt 0) { $vf = "$vf,scale=${ScaleW}:-2" }
& $ffmpeg -hide_banner -loglevel error -i $clip -vf $vf (Join-Path $dir "f_%04d.png")
$n = (Get-ChildItem $dir -Filter "f_*.png").Count
"frames=$n"
"dir=$dir"
