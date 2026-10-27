# -*- coding: utf-8 -*-
# 任务16：把任意 PCM WAV 转成 FPGA 需要的裸 PCM —— 48kHz / 16bit / 单声道 / 小端
# 输出内容是【无 WAV 头】的裸 PCM，文件名按扫描器要求命名为 MUSIC.WAV，放 TF 卡根目录。
# 用法:  python wav_to_pcm.py 输入.wav MUSIC.WAV
# 说明:  仅支持 PCM 编码的 wav；mp3/其它格式请先用格式工厂或 ffmpeg 转成 wav。
import wave, sys, struct

TARGET_SR = 48000

def read_mono(inp):
    with wave.open(inp, "rb") as w:
        nch = w.getnchannels()
        sw  = w.getsampwidth()
        sr  = w.getframerate()
        nfr = w.getnframes()
        raw = w.readframes(nfr)
    frames = []
    for i in range(nfr):
        vals = []
        for c in range(nch):
            b = i * nch * sw + c * sw
            if sw == 1:                                   # 8bit 无符号
                v = (raw[b] - 128) * 256
            elif sw == 2:                                 # 16bit
                v = int.from_bytes(raw[b:b+2], "little", signed=True)
            elif sw == 3:                                 # 24bit 取高 16 位
                v = int.from_bytes(raw[b:b+3], "little", signed=True) >> 8
            elif sw == 4:                                 # 32bit 取高 16 位
                v = int.from_bytes(raw[b:b+4], "little", signed=True) >> 16
            else:
                raise ValueError("不支持的位宽: %d 字节" % sw)
            vals.append(v)
        frames.append(sum(vals) // len(vals))             # 混合为单声道
    return frames, sr

def resample_linear(x, sr_in, sr_out):
    if sr_in == sr_out:
        return x
    ratio = sr_in / sr_out
    n = int(len(x) / ratio)
    out = [0] * n
    last = len(x) - 1
    for i in range(n):
        pos = i * ratio
        i0 = int(pos)
        frac = pos - i0
        out[i] = int(x[i0] * (1.0 - frac) + x[min(i0 + 1, last)] * frac)
    return out

def main(inp, outp):
    x, sr = read_mono(inp)
    if sr != TARGET_SR:
        x = resample_linear(x, sr, TARGET_SR)
    x = [v if -32768 <= v <= 32767 else (-32768 if v < 0 else 32767) for v in x]
    pcm = b"".join(struct.pack("<h", v) for v in x)
    rem = len(pcm) % 512                                 # 512 字节对齐，末尾补静音
    if rem:
        pcm += b"\x00" * (512 - rem)
    with open(outp, "wb") as f:
        f.write(pcm)
    print("完成: %d 样本, %.2f 秒, %d 字节, %d 扇区" %
          (len(x), len(x) / TARGET_SR, len(pcm), len(pcm) // 512))

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("用法: python wav_to_pcm.py 输入.wav MUSIC.WAV")
        sys.exit(1)
    main(sys.argv[1], sys.argv[2])
