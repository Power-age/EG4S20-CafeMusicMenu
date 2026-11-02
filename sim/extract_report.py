import docx, os, io

SRC = r"D:\AAA_University\Anlu\官方文件\材料上交\报告"
OUT = r"D:\AAA_University\Anlu\Project\doc\报告\_extract"
os.makedirs(OUT, exist_ok=True)

def dump(name, dst):
    d = docx.Document(os.path.join(SRC, name))
    lines = []
    lines.append("### 文件: %s" % name)
    lines.append("段落数: %d  表格数: %d" % (len(d.paragraphs), len(d.tables)))
    lines.append("")
    lines.append("========== 段落 ==========")
    for i, p in enumerate(d.paragraphs):
        txt = p.text.strip()
        if not txt:
            continue
        lines.append("[%03d][%s] %s" % (i, p.style.name, txt))
    lines.append("")
    lines.append("========== 表格 ==========")
    for ti, t in enumerate(d.tables):
        lines.append("---- 表 %d：%d 行 x %d 列 ----" % (ti + 1, len(t.rows), len(t.columns)))
        for r in t.rows[:30]:
            cells = [c.text.strip().replace("\n", " ") for c in r.cells]
            lines.append(" | ".join(cells))
        lines.append("")
    # 图片数量
    imgs = [r for r in d.part.rels.values() if "image" in r.reltype]
    lines.append("内嵌图片数: %d" % len(imgs))
    io.open(dst, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
    print("dump ->", dst, len(lines), "行")

dump("技术报告模板.docx", os.path.join(OUT, "template.txt"))
dump("作品设计报告.docx", os.path.join(OUT, "draft.txt"))
