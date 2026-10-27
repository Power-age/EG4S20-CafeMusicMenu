"""把三首 MP3 转成 TRACKxx.RAW（48k/16bit/单声道），并把每条峰值归一到同一水平。

这样三条曲目在同一个音量档下频谱高度一致，不会出现某首柱子明显偏矮。
注：ffmpeg 的 volumedetect 报的 max_volume 与裸 PCM 样本峰值约有 0.8 dB 偏差，
    故目标值取 -0.2 dB，实测落到约 -1.0 dBFS（与频谱标定基准一致）。
"""
import re
import subprocess
import sys
from pathlib import Path

FFMPEG = r"D:\Format\FormatFactory\ffmpeg.exe"
SRC = Path(r"D:\AAA_University\Anlu\Project\doc\TF卡\音频")
DST = Path(r"D:\AAA_University\Anlu\Project\doc\TF卡\raw_new")
TARGET_DB = -0.2
TRACKS = [
    ("Airport-Lounge(chosic.com).mp3", "TRACK01.RAW"),
    ("Bossa-Antigua(chosic.com).mp3", "TRACK02.RAW"),
    ("wavemaster-the-jazz-piano-143632.mp3", "TRACK03.RAW"),
]


def peak_db(src):
    r = subprocess.run([FFMPEG, "-hide_banner", "-nostdin", "-i", str(src),
                        "-af", "volumedetect", "-f", "null", "-"],
                       capture_output=True, text=True, encoding="utf-8", errors="ignore")
    m = re.search(r"max_volume:\s*(-?[\d.]+) dB", r.stderr)
    if not m:
        raise RuntimeError("无法解析音量: " + str(src))
    return float(m.group(1))


def main():
    DST.mkdir(parents=True, exist_ok=True)
    for src_name, out_name in TRACKS:
        src = SRC / src_name
        if not src.exists():
            print("缺少源文件:", src)
            return 1
        pk = peak_db(src)
        gain = TARGET_DB - pk
        out = DST / out_name
        cmd = [FFMPEG, "-y", "-nostdin", "-hide_banner", "-loglevel", "error",
               "-i", str(src), "-map", "0:a:0", "-vn", "-ac", "1", "-ar", "48000",
               "-af", "volume=%.2fdB" % gain, "-c:a", "pcm_s16le", "-f", "s16le", str(out)]
        subprocess.run(cmd, check=True)
        print("%-12s <- %-40s 峰值 %6.2f dB -> 增益 %+5.2f dB -> %.2f MB"
              % (out_name, src_name, pk, gain, out.stat().st_size / 1e6))
    print("\n输出目录:", DST)
    return 0


if __name__ == "__main__":
    sys.exit(main())
