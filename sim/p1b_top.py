"""P1b-4：顶层扩到 8 bank。

策略：frame_read_write 只吃 4 个地址 + 2 位索引，因此把 8 bank 分成两组，
在顶层按 idx[2] 选组、把该组的 4 个基地址喂进去，索引只传 idx[1:0]。
这样底层 FIFO/读写模块一行都不用改。
"""
import io

P = r"D:\AAA_University\Anlu\Project\src\user_source\hdl_source\top_tf_hdmi_audio.v"
txt = io.open(P, encoding="utf-8", errors="surrogateescape").read()

REPL = [
    # ---- bank 地址：加 4~7 ----
    ("parameter BANK3_ADDR    = FRAME_PIXELS*24'd3;",
     "parameter BANK3_ADDR    = FRAME_PIXELS*24'd3;\n"
     "parameter BANK4_ADDR    = FRAME_PIXELS*24'd4;\n"
     "parameter BANK5_ADDR    = FRAME_PIXELS*24'd5;\n"
     "parameter BANK6_ADDR    = FRAME_PIXELS*24'd6;\n"
     "parameter BANK7_ADDR    = FRAME_PIXELS*24'd7;"),
    # ---- 索引/有效位宽度 ----
    ("reg  [1:0]  e2_disp_buf_meta;", "reg  [2:0]  e2_disp_buf_meta;"),
    ("reg  [1:0]  e2_disp_buf_sync;", "reg  [2:0]  e2_disp_buf_sync;"),
    ("reg  [1:0]  e2_disp_buf_prev;", "reg  [2:0]  e2_disp_buf_prev;"),
    ("reg  [1:0]  e2_fade_read_buf_idx;", "reg  [2:0]  e2_fade_read_buf_idx;"),
    ("reg  [1:0]  e2_fade_target_buf_idx;", "reg  [2:0]  e2_fade_target_buf_idx;"),
    ("wire [1:0]  frame_read_buf_idx;", "wire [2:0]  frame_read_buf_idx;"),
    ("wire [3:0]  bank_valid_wire;", "wire [7:0]  bank_valid_wire;"),
    ("wire [1:0]  img_idx_wire;", "wire [2:0]  img_idx_wire;"),
    ("reg  [3:0]  bv_meta, bv_sync;         // bank_valid -> video",
     "reg  [7:0]  bv_meta, bv_sync;         // bank_valid -> video"),
    ("wire [1:0]  resident_target;          // 常驻挂起目标（转场映射）",
     "wire [2:0]  resident_target;          // 常驻挂起目标（转场映射）"),
    ("wire [1:0]  write_buf_idx;", "wire [2:0]  write_buf_idx;"),
    ("wire [1:0]  disp_buf_idx;", "wire [2:0]  disp_buf_idx;"),
    # ---- 复位值 ----
    ("e2_disp_buf_meta <= 2'd0;", "e2_disp_buf_meta <= 3'd0;"),
    ("e2_disp_buf_sync <= 2'd0;", "e2_disp_buf_sync <= 3'd0;"),
    ("e2_disp_buf_prev <= 2'd0;", "e2_disp_buf_prev <= 3'd0;"),
    ("e2_fade_read_buf_idx <= 2'd0;", "e2_fade_read_buf_idx <= 3'd0;"),
    ("e2_fade_target_buf_idx <= 2'd0;", "e2_fade_target_buf_idx <= 3'd0;"),
    ("bv_meta  <= 4'd0;  bv_sync  <= 4'd0;", "bv_meta  <= 8'd0;  bv_sync  <= 8'd0;"),
    # ---- 读/写地址：按组选（idx[2]）----
    ("""wire [20:0] rd_addr_0 = zoom_en_v ? (BANK0_ADDR[20:0] + ZOOM_ROW_BASE) : BANK0_ADDR[20:0];
wire [20:0] rd_addr_1 = zoom_en_v ? (BANK1_ADDR[20:0] + ZOOM_ROW_BASE) : BANK1_ADDR[20:0];
wire [20:0] rd_addr_2 = zoom_en_v ? (BANK2_ADDR[20:0] + ZOOM_ROW_BASE) : BANK2_ADDR[20:0];
wire [20:0] rd_addr_3 = zoom_en_v ? (BANK3_ADDR[20:0] + ZOOM_ROW_BASE) : BANK3_ADDR[20:0];""",
     """// 8 bank 分两组：低位 [1:0] 选组内偏移，高位 [2] 选组
wire [23:0] rd_base0 = frame_read_buf_idx[2] ? BANK4_ADDR : BANK0_ADDR;
wire [23:0] rd_base1 = frame_read_buf_idx[2] ? BANK5_ADDR : BANK1_ADDR;
wire [23:0] rd_base2 = frame_read_buf_idx[2] ? BANK6_ADDR : BANK2_ADDR;
wire [23:0] rd_base3 = frame_read_buf_idx[2] ? BANK7_ADDR : BANK3_ADDR;
wire [20:0] rd_addr_0 = zoom_en_v ? (rd_base0[20:0] + ZOOM_ROW_BASE) : rd_base0[20:0];
wire [20:0] rd_addr_1 = zoom_en_v ? (rd_base1[20:0] + ZOOM_ROW_BASE) : rd_base1[20:0];
wire [20:0] rd_addr_2 = zoom_en_v ? (rd_base2[20:0] + ZOOM_ROW_BASE) : rd_base2[20:0];
wire [20:0] rd_addr_3 = zoom_en_v ? (rd_base3[20:0] + ZOOM_ROW_BASE) : rd_base3[20:0];"""),
    (".read_addr_index   (frame_read_buf_idx),",
     ".read_addr_index   (frame_read_buf_idx[1:0]),"),
    ("""    .write_addr_0      (BANK0_ADDR),
    .write_addr_1      (BANK1_ADDR),
    .write_addr_2      (BANK2_ADDR),
    .write_addr_3      (BANK3_ADDR),
    .write_addr_index  (write_buf_idx),""",
     """    .write_addr_0      (write_buf_idx[2] ? BANK4_ADDR : BANK0_ADDR),
    .write_addr_1      (write_buf_idx[2] ? BANK5_ADDR : BANK1_ADDR),
    .write_addr_2      (write_buf_idx[2] ? BANK6_ADDR : BANK2_ADDR),
    .write_addr_3      (write_buf_idx[2] ? BANK7_ADDR : BANK3_ADDR),
    .write_addr_index  (write_buf_idx[1:0]),"""),
]

miss = []
for old, new in REPL:
    if old in txt:
        txt = txt.replace(old, new, 1)
    else:
        miss.append(old.split("\n")[0][:70])

io.open(P, "w", encoding="utf-8", errors="surrogateescape", newline="\n").write(txt)
print("应用替换:", len(REPL) - len(miss), "/", len(REPL))
for m in miss:
    print("  未命中:", m)
