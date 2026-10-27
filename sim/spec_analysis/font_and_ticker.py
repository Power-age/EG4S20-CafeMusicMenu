"""补 6 个标点字形到 5x7 字库，并生成滚动字幕的文本 ROM。

字库格式：1024 项 = 128 字符 × 8 行；每行低 5 位有效，bit4 = 最左像素。
"""
import shutil
from pathlib import Path

HDL = Path(r"D:\AAA_University\Anlu\Project\src\user_source\hdl_source")
MEM = HDL / "font5x7_data.mem"
MIF = HDL / "font5x7_data.mif"

# 行序：7 行字形 + 1 行空白；bit4=左
GLYPHS = {
    33: [0x04, 0x04, 0x04, 0x04, 0x04, 0x00, 0x04, 0x00],  # !
    44: [0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C, 0x08, 0x00],  # ,
    45: [0x00, 0x00, 0x00, 0x0E, 0x00, 0x00, 0x00, 0x00],  # -
    46: [0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C, 0x00],  # .
    47: [0x01, 0x02, 0x02, 0x04, 0x08, 0x08, 0x10, 0x00],  # /
    63: [0x0E, 0x11, 0x01, 0x02, 0x04, 0x00, 0x04, 0x00],  # ?
}


def art(rows):
    return "\n".join("    " + "".join("#" if r & (1 << (4 - i)) else "." for i in range(5)) for r in rows)


def patch_font():
    lines = [l.strip() for l in MEM.read_text(encoding="ascii").splitlines() if l.strip()]
    assert len(lines) == 1024, len(lines)
    data = [int(l, 16) for l in lines]
    for code, rows in GLYPHS.items():
        for r, v in enumerate(rows):
            data[code * 8 + r] = v

    shutil.copy2(MEM, MEM.with_suffix(".mem.bak"))
    shutil.copy2(MIF, MIF.with_suffix(".mif.bak"))

    MEM.write_text("\n".join("%02X" % v for v in data) + "\n", encoding="ascii")
    out = ["WIDTH=8;", "DEPTH=1024;", "ADDRESS_RADIX=UNS;", "DATA_RADIX=HEX;", "CONTENT BEGIN"]
    out += ["  %d : %02X;" % (i, v) for i, v in enumerate(data)]
    out += ["END;"]
    MIF.write_text("\n".join(out) + "\n", encoding="ascii")
    return data


def make_ticker():
    # 每条 <= 32 字符，保证一个字幕窗口能完整显示（窗口 256 列 / 8 = 32 字符）
    captions = [
        "TODAY - SOURDOUGH AT 15:00",
        "CLOSING 21:00 - SEE YOU SOON",
        "ROOM 2 - NEW PHOTOGRAPHS",
        "MORNING LIGHT - FIRST CUP",
    ]
    SLOT, SPAN = 64, 48
    rom = [0x20] * (SLOT * 4)
    for i, cap in enumerate(captions):
        assert len(cap) <= SPAN, (i, len(cap))
        for j, ch in enumerate(cap):
            assert 32 <= ord(ch) < 128, ch
            rom[i * SLOT + j] = ord(ch)
    out = ["WIDTH=8;", "DEPTH=256;", "ADDRESS_RADIX=UNS;", "DATA_RADIX=HEX;", "CONTENT BEGIN"]
    out += ["  %d : %02X;" % (i, v) for i, v in enumerate(rom)]
    out += ["END;"]
    (HDL / "ticker_text.mif").write_text("\n".join(out) + "\n", encoding="ascii")
    (HDL / "ticker_text.mem").write_text("\n".join("%02X" % v for v in rom) + "\n", encoding="ascii")
    return captions


if __name__ == "__main__":
    data = patch_font()
    for code, rows in GLYPHS.items():
        print("char '%s' (%d):" % (chr(code), code))
        print(art(rows))
    caps = make_ticker()
    used = set()
    for cap in caps:
        used |= set(cap)
    blanks = sorted(c for c in used if all(v == 0 for v in data[ord(c) * 8:ord(c) * 8 + 8]))
    print("\n字幕文案用到的字符:", "".join(sorted(used)))
    print("其中仍为空白字形的:", blanks if blanks else "无（全部有字形）")
    print("字符数:", [len(c) for c in caps])
