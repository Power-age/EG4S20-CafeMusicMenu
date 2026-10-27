"""把三首曲子转成 TRACKxx.RAW（48k/16bit/单声道），逐条峰值归一到约 -1 dBFS，并写卡。"""
import re, shutil, subprocess
from pathlib import Path

FFMPEG = r"D:\Format\FormatFactory\ffmpeg.exe"
SRC = Path(r"D:\AAA_University\Anlu\Project\doc\TF卡\音频")
DST = Path(r"D:\AAA_University\Anlu\Project\doc\TF卡\raw_new")
TARGET_DB = -0.2   # volumedetect 与裸 PCM 峰值差约 0.8 dB，落点约 -1 dBFS

TRACKS = [
    ("Scott_Joplin_-_03_-_Maple_Leaf_Rag_1899_Z_Brewster-Geisz_version(chosic.com).mp3", "TRACK01.RAW"),
    ("wavemaster-the-jazz-piano-143632.mp3", "TRACK02.RAW"),
    ("Fig-leaf-rag-by-Kevin-Macleod.mp3", "TRACK03.RAW"),
]


def peak_db(src):
    r = subprocess.run([FFMPEG, "-hide_banner", "-nostdin", "-i", str(src),
                        "-af", "volumedetect", "-f", "null", "-"],
                       capture_output=True, text=True, encoding="utf-8", errors="ignore")
    m = re.search(r"max_volume:\s*(-?[\d.]+) dB", r.stderr)
    return float(m.group(1)) if m else None


DST.mkdir(parents=True, exist_ok=True)
outs = []
for name, out in TRACKS:
    src = SRC / name
    if not src.exists():
        print("缺少源文件:", name); continue
    pk = peak_db(src)
    if pk is None:
        print("音量解析失败:", name); continue
    gain = TARGET_DB - pk
    dst = DST / out
    subprocess.run([FFMPEG, "-y", "-nostdin", "-hide_banner", "-loglevel", "error",
                    "-i", str(src), "-map", "0:a:0", "-vn", "-ac", "1", "-ar", "48000",
                    "-af", "volume=%.2fdB" % gain, "-c:a", "pcm_s16le", "-f", "s16le", str(dst)],
                   check=True)
    outs.append(dst)
    print("%-12s <- %-46s 峰值 %6.2f dB -> 增益 %+5.2f dB -> %.2f MB"
          % (out, name[:46], pk, gain, dst.stat().st_size / 1e6))

# 写卡
card = Path("F:/")
if card.exists():
    for f in outs:
        shutil.copy2(str(f), str(card / f.name))
        print("已写卡:", f.name)
else:
    print("F: 不可访问，仅生成到 raw_new")
