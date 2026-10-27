import io
from docx import Document

d = Document(r"D:\AAA_University\Anlu\Project\doc\作品简介.docx")
t = [p.text for p in d.paragraphs if p.text.strip()]
out = []
out.append("paras=%d total_chars=%d" % (len(t), sum(len(x) for x in t)))
for x in t:
    out.append("---")
    out.append(x)
io.open(r"D:\AAA_University\Anlu\Project\sim\intro_dump.txt", "w", encoding="utf-8").write("\n".join(out))
print("\n".join(out[:2]))
