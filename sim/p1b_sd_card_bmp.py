"""P1b-2：把 sd_card_bmp 从 4 bank 扩到 8 bank（索引/掩码/查表/清屏/装载循环）。

每个替换都断言命中，避免静默漏改。
"""
import io
import sys

P = r"D:\AAA_University\Anlu\Project\src\user_source\hdl_source\SD\sd_card_bmp.v"
txt = io.open(P, encoding="utf-8", errors="surrogateescape").read()

REPL = [
    # ---- 端口宽度 ----
    ("output [3:0]                bank_valid_out,",
     "output [7:0]                bank_valid_out,"),
    ("output [1:0]                img_idx_out,",
     "output [2:0]                img_idx_out,"),
    ("output reg [1:0]            geom_bank,      // 该几何属于哪个 bank",
     "output reg [2:0]            geom_bank,      // 该几何属于哪个 bank"),
    ("output reg [1:0]            disp_buf_idx,",
     "output reg [2:0]            disp_buf_idx,"),
    # ---- 扫描结果 ----
    ("wire [3:0]  scn_resource_valid;",
     "wire [7:0]  scn_resource_valid;"),
    ("wire [31:0] scn_res3_size;",
     "wire [31:0] scn_res3_size;\nwire [31:0] scn_res4_cluster;\nwire [31:0] scn_res5_cluster;\n"
     "wire [31:0] scn_res6_cluster;\nwire [31:0] scn_res7_cluster;\n"
     "wire [31:0] scn_res4_size;\nwire [31:0] scn_res5_size;\nwire [31:0] scn_res6_size;\n"
     "wire [31:0] scn_res7_size;"),
    # ---- 内部寄存器宽度 ----
    ("reg [2:0]        img_found_count;", "reg [3:0]        img_found_count;"),
    ("reg [1:0]        load_idx;             // 当前正在写入的图片编号",
     "reg [2:0]        load_idx;             // 当前正在写入的图片编号"),
    ("reg [1:0]        pending_buf_idx;      // 当前正在写入的目标缓冲区",
     "reg [2:0]        pending_buf_idx;      // 当前正在写入的目标缓冲区"),
    ("reg [3:0]        bad_image_mask;", "reg [7:0]        bad_image_mask;"),
    ("reg [3:0]        bank_valid;", "reg [7:0]        bank_valid;"),
    ("reg [2:0]        next_load_idx;", "reg [3:0]        next_load_idx;"),
    ("reg [1:0]  load_write_buf_idx;", "reg [2:0]  load_write_buf_idx;"),
    ("reg [1:0]  clear_bank;", "reg [2:0]  clear_bank;"),
    # ---- 图像元数据寄存器：加 4..7 ----
    ("reg [31:0]  img_cluster3;",
     "reg [31:0]  img_cluster3;\n    reg [31:0]  img_cluster4;\n    reg [31:0]  img_cluster5;\n"
     "    reg [31:0]  img_cluster6;\n    reg [31:0]  img_cluster7;"),
    ("reg [31:0]  img_file_size3;",
     "reg [31:0]  img_file_size3;\n    reg [31:0]  img_file_size4;\n    reg [31:0]  img_file_size5;\n"
     "    reg [31:0]  img_file_size6;\n    reg [31:0]  img_file_size7;"),
    # ---- 复位/清空值 ----
    ("img_found_count       <= 3'd0;", "img_found_count       <= 4'd0;"),
    ("load_idx              <= 2'd0;", "load_idx              <= 3'd0;"),
    ("pending_buf_idx       <= 2'd0;", "pending_buf_idx       <= 3'd0;"),
    ("load_write_buf_idx    <= 2'd0;", "load_write_buf_idx    <= 3'd0;"),
    ("disp_buf_idx          <= 2'd0;", "disp_buf_idx          <= 3'd0;"),
    ("bad_image_mask        <= 4'd0;", "bad_image_mask        <= 8'd0;"),
    ("bank_valid            <= 4'd0;", "bank_valid            <= 8'd0;"),
    ("next_load_idx         <= 3'd0;", "next_load_idx         <= 4'd0;"),
    ("clear_bank   <= 2'd0;", "clear_bank   <= 3'd0;"),
    ("geom_bank             <= 2'd0;", "geom_bank             <= 3'd0;"),
    # ---- 清屏：4 bank -> 8 bank ----
    ("if (clear_bank == 2'd3) begin", "if (clear_bank == 3'd7) begin"),
    ("clear_bank <= clear_bank + 2'd1;", "clear_bank <= clear_bank + 3'd1;"),
    # ---- 装载循环索引 ----
    ("load_idx          <= next_load_idx[1:0];", "load_idx          <= next_load_idx[2:0];"),
    ("load_cluster      <= cluster_lut(next_load_idx[1:0]);",
     "load_cluster      <= cluster_lut(next_load_idx[2:0]);"),
    ("pending_buf_idx   <= next_load_idx[1:0];", "pending_buf_idx   <= next_load_idx[2:0];"),
    ("load_write_buf_idx <= next_load_idx[1:0];", "load_write_buf_idx <= next_load_idx[2:0];"),
    ("next_load_idx     <= next_load_idx + 3'd1;", "next_load_idx     <= next_load_idx + 4'd1;"),
    # ---- 查表函数：8 项 ----
    ("""function good_image_exists;
    input [2:0] count;
    input [3:0] bad_mask;
    integer idx;
    begin
        good_image_exists = 1'b0;
        for (idx = 0; idx < 4; idx = idx + 1)
            if ((idx < count) && !bad_mask[idx])
                good_image_exists = 1'b1;
    end
endfunction""",
     """function good_image_exists;
    input [3:0] count;
    input [7:0] bad_mask;
    integer idx;
    begin
        good_image_exists = 1'b0;
        for (idx = 0; idx < 8; idx = idx + 1)
            if ((idx < count) && !bad_mask[idx])
                good_image_exists = 1'b1;
    end
endfunction"""),
    ("""function [31:0] file_size_lut;
    input [1:0] idx;
    begin
        case (idx)
            2'd0: file_size_lut = img_file_size0;
            2'd1: file_size_lut = img_file_size1;
            2'd2: file_size_lut = img_file_size2;
            2'd3: file_size_lut = img_file_size3;
            default: file_size_lut = 32'd0;
        endcase
    end
endfunction""",
     """function [31:0] file_size_lut;
    input [2:0] idx;
    begin
        case (idx)
            3'd0: file_size_lut = img_file_size0;
            3'd1: file_size_lut = img_file_size1;
            3'd2: file_size_lut = img_file_size2;
            3'd3: file_size_lut = img_file_size3;
            3'd4: file_size_lut = img_file_size4;
            3'd5: file_size_lut = img_file_size5;
            3'd6: file_size_lut = img_file_size6;
            default: file_size_lut = img_file_size7;
        endcase
    end
endfunction"""),
    ("""function [31:0] cluster_lut;
    input [1:0] idx;
    begin
        case (idx)
            2'd0: cluster_lut = img_cluster0;
            2'd1: cluster_lut = img_cluster1;
            2'd2: cluster_lut = img_cluster2;
            2'd3: cluster_lut = img_cluster3;
            default: cluster_lut = img_cluster0;
        endcase
    end
endfunction""",
     """function [31:0] cluster_lut;
    input [2:0] idx;
    begin
        case (idx)
            3'd0: cluster_lut = img_cluster0;
            3'd1: cluster_lut = img_cluster1;
            3'd2: cluster_lut = img_cluster2;
            3'd3: cluster_lut = img_cluster3;
            3'd4: cluster_lut = img_cluster4;
            3'd5: cluster_lut = img_cluster5;
            3'd6: cluster_lut = img_cluster6;
            default: cluster_lut = img_cluster7;
        endcase
    end
endfunction"""),
    # ---- 扫描缓存：8 张 ----
    ("""                img_cluster0 <= scn_resource_valid[0] ? scn_res0_cluster : 32'd0;
                img_cluster1 <= scn_resource_valid[1] ? scn_res1_cluster : 32'd0;
                img_cluster2 <= scn_resource_valid[2] ? scn_res2_cluster : 32'd0;
                img_cluster3 <= scn_resource_valid[3] ? scn_res3_cluster : 32'd0;
                img_file_size0 <= scn_resource_valid[0] ? scn_res0_size : 32'd0;
                img_file_size1 <= scn_resource_valid[1] ? scn_res1_size : 32'd0;
                img_file_size2 <= scn_resource_valid[2] ? scn_res2_size : 32'd0;
                img_file_size3 <= scn_resource_valid[3] ? scn_res3_size : 32'd0;
                img_found_count <= {2'd0,scn_resource_valid[0]} + {2'd0,scn_resource_valid[1]}
                                 + {2'd0,scn_resource_valid[2]} + {2'd0,scn_resource_valid[3]};""",
     """                img_cluster0 <= scn_resource_valid[0] ? scn_res0_cluster : 32'd0;
                img_cluster1 <= scn_resource_valid[1] ? scn_res1_cluster : 32'd0;
                img_cluster2 <= scn_resource_valid[2] ? scn_res2_cluster : 32'd0;
                img_cluster3 <= scn_resource_valid[3] ? scn_res3_cluster : 32'd0;
                img_cluster4 <= scn_resource_valid[4] ? scn_res4_cluster : 32'd0;
                img_cluster5 <= scn_resource_valid[5] ? scn_res5_cluster : 32'd0;
                img_cluster6 <= scn_resource_valid[6] ? scn_res6_cluster : 32'd0;
                img_cluster7 <= scn_resource_valid[7] ? scn_res7_cluster : 32'd0;
                img_file_size0 <= scn_resource_valid[0] ? scn_res0_size : 32'd0;
                img_file_size1 <= scn_resource_valid[1] ? scn_res1_size : 32'd0;
                img_file_size2 <= scn_resource_valid[2] ? scn_res2_size : 32'd0;
                img_file_size3 <= scn_resource_valid[3] ? scn_res3_size : 32'd0;
                img_file_size4 <= scn_resource_valid[4] ? scn_res4_size : 32'd0;
                img_file_size5 <= scn_resource_valid[5] ? scn_res5_size : 32'd0;
                img_file_size6 <= scn_resource_valid[6] ? scn_res6_size : 32'd0;
                img_file_size7 <= scn_resource_valid[7] ? scn_res7_size : 32'd0;
                img_found_count <= {3'd0,scn_resource_valid[0]} + {3'd0,scn_resource_valid[1]}
                                 + {3'd0,scn_resource_valid[2]} + {3'd0,scn_resource_valid[3]}
                                 + {3'd0,scn_resource_valid[4]} + {3'd0,scn_resource_valid[5]}
                                 + {3'd0,scn_resource_valid[6]} + {3'd0,scn_resource_valid[7]};"""),
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
