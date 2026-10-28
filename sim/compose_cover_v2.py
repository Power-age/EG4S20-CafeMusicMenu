from PIL import Image, ImageDraw, ImageFont, ImageFilter

SRC = r"D:\AAA_University\Anlu\Project\doc\TF卡\bmp\好图\咖啡店面图_v2.png"
PREVIEW = r"D:\AAA_University\Anlu\Project\sim\cover_v2_preview.png"

FONT_CN = r"C:\Windows\Fonts\msyhbd.ttc"
FONT_EN = r"C:\Windows\Fonts\msyh.ttc"

NAME = "木与豆咖啡"
EN = "W O O D   &   B E A N"
SLOGAN = "每日现磨 · 手冲与意式"

DARK = (58, 34, 20, 255)
DARK_SOFT = (58, 34, 20, 225)

im = Image.open(SRC).convert("RGB")
if im.size == (1448, 1086):
    im = im.crop((57, 0, 1390, 1000))   # 去掉底部深色边，保持 4:3
W, H = im.size

f_name = ImageFont.truetype(FONT_CN, 126)
f_en = ImageFont.truetype(FONT_EN, 38)
f_sl = ImageFont.truetype(FONT_CN, 40)

layer = Image.new("RGBA", im.size, (0, 0, 0, 0))
d = ImageDraw.Draw(layer)

def centered(text, font, y, fill, stroke=0, stroke_fill=None):
    w = d.textlength(text, font=font)
    d.text(((W - w) / 2, y), text, font=font, fill=fill,
           stroke_width=stroke, stroke_fill=stroke_fill)

# 柔和白色光晕，保证深棕字压在亮天空上也干净
glow = Image.new("RGBA", im.size, (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
for text, font, y in ((NAME, f_name, 88), (EN, f_en, 240), (SLOGAN, f_sl, 310)):
    w = gd.textlength(text, font=font)
    gd.text(((W - w) / 2, y), text, font=font, fill=(255, 250, 240, 150),
            stroke_width=8, stroke_fill=(255, 250, 240, 110))
glow = glow.filter(ImageFilter.GaussianBlur(9))

base = im.convert("RGBA")
base.alpha_composite(glow)
centered(NAME, f_name, 88, DARK, 2, (255, 248, 236, 120))
centered(EN, f_en, 240, DARK_SOFT)
centered(SLOGAN, f_sl, 310, DARK_SOFT)
base.alpha_composite(layer)

out = base.convert("RGB")
out.save(PREVIEW)
out.resize((480, 360), Image.LANCZOS).save(r"D:\AAA_University\Anlu\Project\sim\cover_v2_480.png")
print("saved", out.size)
