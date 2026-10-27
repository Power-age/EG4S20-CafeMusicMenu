import io, os, sys

MODULES = [
    "menu_controller.v", "menu_renderer.v", "spectrum_engine.v", "spectrum_render.v",
    "src_info_render.v", "subtitle_render.v", "track_countdown.v", "video_effect_overlay.v",
    "font5x7_rom.v", "mask_overlay.v", "mask_slide.v", "video_zoom.v", "tone_dds.v",
]

AL = r"D:\AAA_University\Anlu\Project\src\td_project\HDMI1.4b_Transmitter_v1.0.al"
PRJS = [
    r"D:\AAA_University\Anlu\Project\src\td_project\HDMI1.4b_Transmitter_v1.0_Runs\syn_1\HDMI1.4b_Transmitter_v1.0.prj",
    r"D:\AAA_University\Anlu\Project\src\td_project\HDMI1.4b_Transmitter_v1.0_Runs\phy_1\HDMI1.4b_Transmitter_v1.0.prj",
]

def entry(prefix, name, order):
    return (
        '            <File Path="%shdl_source/%s">\n'
        '                <FileInfo>\n'
        '                    <Attr Name="UsedInSyn" Val="true"/>\n'
        '                    <Attr Name="UsedInP&R" Val="true"/>\n'
        '                    <Attr Name="BelongTo" Val="design_1"/>\n'
        '                    <Attr Name="CompileOrder" Val="%d"/>\n'
        '                </FileInfo>\n'
        '            </File>\n' % (prefix, name, order)
    )

def patch(path, prefix, start_order):
    txt = io.open(path, encoding="utf-8").read()
    anchor = "        </Verilog>"
    if anchor not in txt:
        print("ANCHOR_MISSING", path)
        return
    missing = [m for m in MODULES if ('hdl_source/%s"' % m) not in txt]
    if not missing:
        print("ALREADY_OK", os.path.basename(path))
        return
    block = "".join(entry(prefix, m, start_order + i) for i, m in enumerate(missing))
    out = txt.replace(anchor, block + anchor, 1)
    io.open(path, "w", encoding="utf-8", newline="").write(out)
    print("PATCHED", os.path.basename(path), "added", len(missing), "->", ",".join(missing))

patch(AL, "../user_source/", 64)
for p in PRJS:
    patch(p, "../../../user_source/", 66)
