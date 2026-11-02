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
    W, H = im.size
    y0 = int(H * 0.55)
    strip = im.crop((0, y0, W, H)).copy()
    d = ImageDraw.Draw(strip)
    # 网格每 100px（原图坐标）
    for x in range(0, W, 100):
        d.line([(x, 0), (x, strip.height)], fill=(0, 255, 0), width=1)
        d.text((x + 2, 2), str(x), font=ImageFont.truetype(F, 14), fill=(0, 255, 0))
    for yy in range(y0, H, 100):
        y = yy - y0
        if 0 <= y < strip.height:
            d.line([(0, y), (W, y)], fill=(0, 255, 0), width=1)
            d.text((2, y + 1), str(yy), font=ImageFont.truetype(F, 14), fill=(0, 255, 0))
    sw = 760
    strip = strip.resize((sw, max(1, int(strip.height * sw / W))), Image.LANCZOS)
    d2 = ImageDraw.Draw(strip)
    d2.text((6, 18), name, font=ImageFont.truetype(F, 16), fill=(255, 80, 80))
    tiles.append(strip)

maxh = max(t.height for t in tiles)
sheet = Image.new("RGB", (sum(t.width for t in tiles) + 6 * len(tiles), maxh), (15, 15, 15))
x = 0
for t in tiles:
    sheet.paste(t, (x, 0))
    x += t.width + 6
sheet.save(os.path.join(CV, "grid_prices.png"))
print("网格图:", os.path.join(CV, "grid_prices.png"), sheet.size)
