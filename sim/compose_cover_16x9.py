"""16:9 正式封面（1280x720）：内容铺满整幅，黑边交给 FPGA 生成。

设计：与 4:3 封面同一套视觉（深棕店名 + 英文 + slogan，白色光晕），
      但画布改为 16:9，标题放在天空区。
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SRC = r"D:\AAA_University\Anlu\Project\doc\TF卡\bmp\好图\咖啡店面图_v2.png"
OUT = r"D:\AAA_University\Anlu\Project\doc\TF卡\bmp\好图\菜单图_v3_封面\PIC1_16x9_1280x720.BMP"
PREVIEW = r"D:\AAA_University\Anlu\Project\sim\diag_covers\preview_cover16x9.png"

FONT_CN = r"C:\Windows\Fonts\msyhbd.ttc"
FONT_EN = r"C:\Windows\Fonts\msyh.ttc"

NAME = "木与豆咖啡"
EN = "W O O D   &   B E A N"
SLOGAN = "每日现磨 · 手冲与意式"

W, H = 1280, 720

im = Image.open(SRC).convert("RGB")
# 取 16:9 内接（按宽度裁高度，保留天空与店面主体）
crop_h = int(im.width * 9 / 16)
top = max(0, int((im.height - crop_h) * 0.35))
im = im.crop((0, top, im.width, top + crop_h)).resize((W, H), Image.LANCZOS)

f_name = ImageFont.truetype(FONT_CN, 104)
f_en = ImageFont.truetype(FONT_EN, 34)
f_sl = ImageFont.truetype(FONT_CN, 40)

layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(layer)


def centered(draw, text, font, y, fill):
    w = draw.textlength(text, font=font)
    draw.text(((W - w) / 2, y), text, font=font, fill=fill)


glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
for text, font, y in ((NAME, f_name, 52), (EN, f_en, 180), (SLOGAN, f_sl, 232)):
    w = gd.textlength(text, font=font)
    gd.text(((W - w) / 2, y), text, font=font, fill=(255, 250, 240, 160),
            stroke_width=7, stroke_fill=(255, 250, 240, 120))
glow = glow.filter(ImageFilter.GaussianBlur(8))
im = Image.alpha_composite(im.convert("RGBA"), glow)

d = ImageDraw.Draw(im)
centered(d, NAME, f_name, 52, (58, 34, 20, 255))
centered(d, EN, f_en, 180, (58, 34, 20, 235))
centered(d, SLOGAN, f_sl, 232, (58, 34, 20, 225))

im = im.convert("RGB")
im.save(OUT, format="BMP")
im.save(PREVIEW)
print("生成:", OUT, im.size)
