"""更接近真实音乐的测试信号：粉噪声 + 时变共振峰(3 个) + 贝斯 + 高频瞬态。
用 STFT 在频域塑形，保证峰值/谷值随时间移动。"""
import numpy as np

FS = 48000


def _stft(x, n=1024, hop=256):
    w = np.hanning(n)
    frames = 1 + (len(x) - n) // hop
    S = np.empty((frames, n // 2 + 1), dtype=complex)
    for i in range(frames):
        seg = x[i * hop:i * hop + n] * w
        S[i] = np.fft.rfft(seg)
    return S, w


def _istft(S, w, n=1024, hop=256):
    frames = S.shape[0]
    out = np.zeros((frames - 1) * hop + n)
    norm = np.zeros_like(out)
    for i in range(frames):
        seg = np.fft.irfft(S[i], n) * w
        out[i * hop:i * hop + n] += seg
        norm[i * hop:i * hop + n] += w * w
    norm[norm < 1e-9] = 1.0
    return out / norm


def make_music_v2(seconds=12.0, seed=11):
    rng = np.random.default_rng(seed)
    n = int(FS * seconds)
    f = np.fft.rfftfreq(n, 1 / FS)
    f[0] = f[1]
    W = np.fft.rfft(rng.normal(size=n)) / np.sqrt(f)     # 1/f 底噪
    x = np.fft.irfft(W, n)
    x /= np.max(np.abs(x))

    S, w = _stft(x)
    freqs = np.fft.rfftfreq(1024, 1 / FS)
    lf = np.log2(np.maximum(freqs, 20.0))
    t = np.arange(S.shape[0]) * 256 / FS

    # 3 个缓慢游走的共振峰
    G = np.ones_like(lf)
    for k, (c0, span, rate, gain) in enumerate([(500, 350, 0.31, 6.0),
                                                (1400, 700, 0.23, 7.0),
                                                (3200, 1200, 0.19, 5.0)]):
        fc = c0 * 2 ** (span / c0 * 0.35 * np.sin(2 * np.pi * rate * t + k * 2.1)
                        + 0.15 * np.sin(2 * np.pi * (rate * 0.37) * t + k))
        lfc = np.log2(np.maximum(fc, 20.0))
        env = np.zeros((S.shape[0], len(freqs)))
        for i in range(S.shape[0]):
            env[i] = gain * np.exp(-0.5 * ((lf - lfc[i]) / 0.55) ** 2)
        G = G * (1.0 + env)
    S = S * G

    # 贝斯（每拍的基音 + 二次谐波，走音阶）
    notes = np.array([110, 138.6, 164.8, 123.5, 146.8, 98.0, 130.8, 174.6])
    bass = np.zeros(S.shape[0])
    for i, ti in enumerate(t):
        idx = int(ti / 0.47) % len(notes)
        ph = (ti % 0.47) / 0.47
        bass[i] = np.exp(-3.0 * ph) * notes[idx]
    for i in range(S.shape[0]):
        if bass[i] > 0:
            for h in (1, 2):
                bin_i = np.argmin(np.abs(freqs - bass[i] * h))
                S[i, max(bin_i - 1, 0):bin_i + 2] *= 6.0
    x2 = _istft(S, w)
    x2 = x2[:n]
    x2 /= np.max(np.abs(x2)) + 1e-9
    x2 *= 0.6
    return (x2 * 32767).astype(np.int64)
