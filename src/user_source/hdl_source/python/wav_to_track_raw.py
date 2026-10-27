import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


def convert(input_path, output_path):
    source = Path(input_path)
    target = Path(output_path)

    if not source.is_file():
        raise ValueError("输入必须是存在的音频文件")
    if not re.fullmatch(r"TRACK(0[1-9]|1[0-6])\.RAW", target.name):
        raise ValueError("输出文件名必须是 TRACK01.RAW 至 TRACK16.RAW")
    if not target.parent.is_dir():
        raise ValueError("输出目录不存在")
    if target.exists():
        raise FileExistsError(f"输出文件已存在，不会覆盖：{target}")

    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        raise RuntimeError("未找到 FFmpeg；请安装 FFmpeg 并将 ffmpeg 加入 PATH")

    fd, temporary = tempfile.mkstemp(prefix=".track_raw_", suffix=".tmp", dir=target.parent)
    os.close(fd)
    try:
        result = subprocess.run(
            [ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error", "-i", str(source),
             "-map", "0:a:0", "-vn", "-ac", "1", "-ar", "48000",
             "-c:a", "pcm_s16le", "-f", "s16le", "-y", temporary],
            capture_output=True,
            text=True,
            errors="replace",
        )
        if result.returncode != 0:
            raise RuntimeError(f"FFmpeg 转换失败：{result.stderr.strip() or '未知错误'}")
        size = os.path.getsize(temporary)
        if size == 0 or size % 2:
            raise RuntimeError("转换结果为空或不是完整的 16 位样本")
        if target.exists():
            raise FileExistsError(f"输出文件已存在，不会覆盖：{target}")
        os.replace(temporary, target)
        return size
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    parser = argparse.ArgumentParser(description="将 FFmpeg 可解码的音频转成工程使用的 48kHz 单声道 16 位裸 PCM")
    parser.add_argument("input", help="输入音频文件（wav/mp3/flac/m4a 等 FFmpeg 可解码格式）")
    parser.add_argument("output", help="输出 TRACK01.RAW 至 TRACK16.RAW")
    args = parser.parse_args()
    try:
        size = convert(args.input, args.output)
    except (OSError, ValueError, RuntimeError) as exc:
        print(f"错误：{exc}", file=sys.stderr)
        return 1
    print(f"已生成 {args.output}（{size} 字节，48kHz / 16bit / 单声道 / 小端裸 PCM）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
