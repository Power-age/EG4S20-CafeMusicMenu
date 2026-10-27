import io, re
from pathlib import Path

HDL = Path(r"D:\AAA_University\Anlu\Project\src\user_source\hdl_source")
TOP = HDL / "top_tf_hdmi_audio.v"

s = io.open(TOP, encoding="utf-8").read()

# ---------- 1) 声明 ----------
s = s.replace("wire [23:0] vout_data;",
              "wire [23:0] vout_data;\nwire [23:0] vout_data_mask;   // 卡内文字叠加后", 1)

# ---------- 2) 实例化（接在 OSD 之后、AXIS 之前）----------
anchor = "video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480("
assert anchor in s
inst = """// ===================== 卡内文字 mask 叠加（最后一级）=====================
mask_overlay u_mask_overlay (
    .clk       (video_clk),
    .rst       (rst_all),
    .de        (osd_de),
    .x         (video_x_cnt[9:0]),
    .y         (video_y_cnt),
    .rgb_in    (vout_data),
    .panel_vis (menu_panel_vis),
    .mask_en   (1'b1),
    .slide_l   (10'd0),
    .slide_r   (10'd0),
    .rgb_out   (vout_data_mask)
);

"""
s = s.replace(anchor, inst + anchor, 1)

# ---------- 3) AXIS 输入改接 mask 输出 ----------
s = s.replace("""        .I_vs          (osd_vs),
        .I_de          (osd_de),
        .I_rgb         (vout_data),""",
"""        .I_vs          (osd_vs),
        .I_de          (osd_de),
        .I_rgb         (vout_data_mask),""")

io.open(TOP, "w", encoding="utf-8", newline="\n").write(s)
print("top 已接线")

# ---------- 4) 登记到两份 .prj ----------
RUNS = Path(r"D:\AAA_University\Anlu\Project\src\td_project\HDMI1.4b_Transmitter_v1.0_Runs")
for prj in [RUNS / "syn_1" / "HDMI1.4b_Transmitter_v1.0.prj", RUNS / "phy_1" / "HDMI1.4b_Transmitter_v1.0.prj"]:
    if not prj.exists():
        print("缺少 prj:", prj); continue
    t = io.open(prj, encoding="utf-8", errors="ignore").read()
    if "mask_overlay.v" in t:
        print("已在 prj:", prj.parent.name); continue
    m = re.search(r"([ \t]*)<File Path=\"\.\./\.\./\.\./user_source/hdl_source/src_info_render\.v\">.*?</File>\n",
                  t, re.S)
    if not m:
        m = re.search(r"([ \t]*)<File Path=\"\.\./\.\./\.\./user_source/hdl_source/[^\"]+\.v\">.*?</File>\n", t, re.S)
    if not m:
        print("未找到插入点:", prj); continue
    block = m.group(0)
    ins = block.replace("src_info_render.v", "mask_overlay.v")
    ins = re.sub(r'Val="\d+"', lambda mo: mo.group(0), ins)
    t = t.replace(block, block + ins, 1)
    io.open(prj, "w", encoding="utf-8", newline="\n").write(t)
    print("已登记 prj:", prj.parent.name)

# ---------- 5) 登记到 .al ----------
for al in (RUNS.parent).glob("*.al"):
    t = io.open(al, encoding="utf-8", errors="ignore").read()
    if "mask_overlay" in t:
        print("已在 al:", al.name); continue
    lines = t.split("\n")
    out = []
    for l in lines:
        out.append(l)
        if "src_info_render.v" in l:
            out.append(l.replace("src_info_render.v", "mask_overlay.v"))
    io.open(al, "w", encoding="utf-8", newline="\n").write("\n".join(out))
    print("已登记 al:", al.name)
