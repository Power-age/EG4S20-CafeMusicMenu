"""三首真曲目交叉验证：选 GS / GOFF / 强调档位。"""
import subprocess
import wave
import numpy as np
from pathlib import Path
from calib import load_wav, collect
from calib2 import simulate, score

FF = r"D:\Format\FormatFactory\ffmpeg.exe"
SRC = Path(r"D:\AAA_University\Anlu\Project\doc\TF卡\音频")
OUT = Path(r"D:\AAA_University\Anlu\Project\sim\spec_analysis")
TAGS = [("周杰伦+霍元甲.mp3", "huoyuanjia"), ("大张伟-阳光彩虹小白马.mp3", "xiaobaima"), ("奶龙大笑_爱给网_aigei_com.mp3", "nailong")]

for name, tag in TAGS:
    wav = OUT / (tag + "_48k.wav")
    npy = OUT / ("fine_" + tag + ".npy")
    if not wav.exists():
        subprocess.run([FF, "-y", "-i", str(SRC / name), "-ac", "1", "-ar", "48000",
                        "-sample_fmt", "s16", str(wav)], capture_output=True)
    if not npy.exists():
        np.save(npy, collect(load_wav(str(wav))))
    print("%-12s %s 块 %d" % (tag, wav.name, np.load(npy).shape[0]))

print()
for tag in [t for _, t in TAGS]:
    F7 = np.load(OUT / ("fine_" + tag + ".npy"))
    print("=== %s ===" % tag)
    for goff, gs in [(48, 3), (52, 2), (54, 2), (56, 2)]:
        score("  GOFF=%d GS=%d" % (goff, gs), simulate(F7, goff, gs, 0))
    print()
