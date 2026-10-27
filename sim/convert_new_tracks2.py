"""两遍法：先按 volumedetect 转一遍，实测裸 PCM 峰值后再修正一次，落到 -1 dBFS。"""
import re, shutil, subprocess
import numpy as np
from pathlib import Path

FFMPEG = r"D:\Format\FormatFactory\ffmpeg.exe"
SRC = Path(r"D:\AAA_University\Anlu\Project\doc\TF卡\音频")
DST = Path(r"D:\AAA_University\Anlu\Project\doc\TF卡\raw_new")
TARGET = -1.0

TRACKS = [
    ("Scott_Joplin_-_03_-_Maple_Leaf_Rag_1899_Z_Brewster-Geisz_version(chosic.com).mp3", "TRACK01.RAW"),
    ("wavemaster-the-jazz-piano-143632.mp3", "TRACK02.RAW"),
    ("Fig-leaf-rag-by-Kevin-Macleod.mp3", "TRACK03.RAW"),
]


def encode(src, dst, gain_db):
    subprocess.run([FFMPEG, "-y", "-nostdin", "-hide_banner", "-loglevel", "error",
                    "-i", str(src), "-map", "0:a:0", "-vn", "-ac", "1", "-ar", "48000",
                    "-af", "volume=%.2fdB" % gain_db, "-c:a", "pcm_s16le", "-f", "s16le", str(dst)],
                   check=True)


def raw_peak_db(p):
    a = np.fromfile(p, dtype="<i2")
    pk = int(np.abs(a.astype(np.int32)).max())
    return 20 * np.log10(pk / 32768.0)


def detect(src):
    r = subprocess.run([FFMPEG, "-hide_banner", "-nostdin", "-i", str(src),
                        "-af", "volumedetect", "-f", "null", "-"],
                       capture_output=True, text=True, encoding="utf-8", errors="ignore")
    m = re.search(r"max_volume:\s*(-?[\d.]+) dB", r.stderr)
    return float(m.group(1))


DST.mkdir(parents=True, exist_ok=True)
outs = []
for name, out in TRACKS:
    src = SRC / name
    dst = DST / out
    g = TARGET - detect(src)
    encode(src, dst, g)
    p1 = raw_peak_db(dst)
    g2 = g + (TARGET - p1)
    encode(src, dst, g2)
    p2 = raw_peak_db(dst)
    outs.append(dst)
    print("%-12s 首轮增益 %+5.2f -> %+.2f dB，修正后 %+5.2f dB，最终峰值 %.2f dBFS，%.2f MB"
          % (out, g, p1, g2, p2, dst.stat().st_size / 1e6))

card = Path("F:/")
if card.exists():
    for f in outs:
        shutil.copy2(str(f), str(card / f.name))
        print("已写卡:", f.name)
