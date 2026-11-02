import os
import shutil
from PIL import Image

CV = r"D:\AAA_University\Anlu\Project\sim\diag_covers"
ASSET = r"D:\AAA_University\Anlu\Project\doc\TF卡\bmp\好图\海报素材"
OUT = r"D:\AAA_University\Anlu\Project\doc\预览图_8页"
os.makedirs(OUT, exist_ok=True)

cov = Image.open(os.path.join(ASSET, "cover.png")).convert("RGB")
cov.resize((640, 480), Image.LANCZOS).save(os.path.join(OUT, "1_封面.png"))

names = [(2, "手冲埃塞俄比亚"), (3, "经典卡布奇诺"), (4, "抹茶拿铁"),
         (5, "巴斯克芝士"), (6, "酸种面包"), (7, "黄油可颂"), (8, "提拉米苏")]
for i, n in names:
    src = os.path.join(CV, "final_p%d.png" % i)
    shutil.copy(src, os.path.join(OUT, "%d_%s.png" % (i, n)))

for f in sorted(os.listdir(OUT)):
    p = os.path.join(OUT, f)
    print("  %-24s %s" % (f, Image.open(p).size))
print("目录:", OUT)
