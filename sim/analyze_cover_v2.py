from PIL import Image
import numpy as np

p = r"D:\AAA_University\Anlu\Project\doc\TF卡\bmp\好图\咖啡店面图_v2.png"
im = Image.open(p).convert("RGB")
a = np.asarray(im).astype(int)
H, W, _ = a.shape
print("size", W, H)

# 逐行判断是否为近白（底部白条检测）
row_mean = a.mean(axis=(1, 2))
white_rows = [y for y in range(H) if row_mean[y] > 245]
print("near-white rows count:", len(white_rows))
if white_rows:
    print("first white row:", white_rows[0], "last:", white_rows[-1])

# 分区平均亮度，帮助判断天空范围
for y0 in range(0, H, 100):
    seg = a[y0:y0 + 100].mean(axis=(0, 1))
    print("y %4d-%4d  RGB %s" % (y0, min(y0 + 100, H), np.round(seg, 1)))
