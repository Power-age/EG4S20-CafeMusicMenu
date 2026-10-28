from PIL import Image

p = r"D:\AAA_University\Anlu\Project\doc\TF卡\bmp\好图\咖啡店面图.png"
im = Image.open(p).convert("RGB")
W, H = im.size
print("size", W, H, "aspect", round(W / H, 4))

px = im.load()

def is_wood(c):
    r, g, b = c
    return 70 <= r <= 190 and 45 <= g <= 150 and 25 <= b <= 115 and r > g > b

for x in (150, 300, 500, 700, 900, 1100, 1300, 1430):
    runs = []
    inside = False
    start = 0
    for y in range(0, int(H * 0.62)):
        w = is_wood(px[x, y])
        if w and not inside:
            inside = True
            start = y
        elif not w and inside:
            inside = False
            if y - start > 25:
                runs.append((start, y))
    if inside and int(H * 0.62) - start > 25:
        runs.append((start, int(H * 0.62)))
    print("x=%4d wood bands: %s" % (x, runs[:4]))
