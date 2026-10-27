"""生成曲名表 ROM（16 槽 × 16 字符），供右上角状态栏显示真歌名。"""
from pathlib import Path

HDL = Path(r"D:\AAA_University\Anlu\Project\src\user_source\hdl_source")
NAMES = [
    "MAPLE LEAF",    # TRACK01
    "JAZZ PIANO",    # TRACK02（保留）
    "FIG LEAF",      # TRACK03
]
SLOT, WIDTH = 16, 12

rom = [0x20] * (SLOT * 16)
for i, nm in enumerate(NAMES):
    assert len(nm) <= WIDTH, (i, len(nm))
    for j, ch in enumerate(nm):
        assert 32 <= ord(ch) < 128, ch
        rom[i * SLOT + j] = ord(ch)

out = ["WIDTH=8;", "DEPTH=256;", "ADDRESS_RADIX=UNS;", "DATA_RADIX=HEX;", "CONTENT BEGIN"]
out += ["  %d : %02X;" % (i, v) for i, v in enumerate(rom)]
out += ["END;"]
(HDL / "track_names.mif").write_text("\n".join(out) + "\n", encoding="ascii")
(HDL / "track_names.mem").write_text("\n".join("%02X" % v for v in rom) + "\n", encoding="ascii")
print("track_names: %d 槽 × %d 字符" % (len(NAMES), WIDTH))
for i, nm in enumerate(NAMES):
    print("  %d: '%s'" % (i, nm))
