import os
from PIL import Image, ImageDraw, ImageFont

ASSET = r"D:\AAA_University\Anlu\Project\doc\TF卡\bmp\好图\海报素材"
CV = r"D:\AAA_University\Anlu\Project\sim\diag_covers"
F = r"C:\Windows\Fonts\msyh.ttc"

pages = ["p2_shouchong.png", "p3_cappuccino.png", "p4_matcha.png",
         "p5_basque.png", "p6_sourdough.png", "p7_croissant.png", "p8_tiramisu.png"]

tiles = []
for name in pages:
    im = Image.open(os.path.join(ASSET, name)).convert("RGB")
    w, h = im.size
    strip = im.crop((0, int(h * 0.60), w, h))     # 底部 40%
    sw = 700
    sh = int(strip.height * sw / strip.width)
    strip = strip.resize((sw, sh), Image.LANCZOS)
    d = ImageDraw.Draw(strip)
    d.rectangle([0, 0, sw - 1, sh - 1], outline=(255, 0, 0), width=2)
    d.text((8, 6), "%s  (%dx%d)  strip y=%d..%d" % (name, w, h, int(h * 0.60), h),
           font=ImageFont.truetype(F, 16), fill=(255, 60, 60))
    tiles.append(strip)

maxh = max(t.height for t in tiles)
sheet = Image.new("RGB", (sum(t.width for t in tiles) + 8 * len(tiles), maxh), (20, 20, 20))
x = 0
for t in tiles:
    sheet.paste(t, (x, 0))
    x += t.width + 8
sheet.save(os.path.join(CV, "price_strips.png"))
print("输出:", os.path.join(CV, "price_strips.png"), sheet.size)
