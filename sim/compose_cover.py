from PIL import Image, ImageDraw, ImageFont, ImageFilter

SRC = r"D:\AAA_University\Anlu\Project\doc\TF卡\bmp\好图\咖啡店面图.png"
PREVIEW = r"D:\AAA_University\Anlu\Project\sim\cover_preview.png"

FONT_CN = r"C:\Windows\Fonts\msyhbd.ttc"
FONT_EN = r"C:\Windows\Fonts\msyh.ttc"

W_txt = "木与豆咖啡"
W_en = "W O O D   &   B E A N"
W_slogan = "每日现磨 · 手冲与意式"

im = Image.open(SRC).convert("RGB")
W, H = im.size

def text_layer(size, draw_fn):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    draw_fn(d, layer)
    return layer

# ---------- 店名 + 英文：贴在木饰面上，按透视倾角旋转 ----------
f_cn = ImageFont.truetype(FONT_CN, 94)
f_en = ImageFont.truetype(FONT_EN, 34)

tmp = Image.new("RGBA", (900, 240), (0, 0, 0, 0))
d = ImageDraw.Draw(tmp)
cn_w = d.textlength(W_txt, font=f_cn)
en_w = d.textlength(W_en, font=f_en)
cx, cy = 450, 120
d.text((cx - cn_w / 2, cy - 92), W_txt, font=f_cn, fill=(250, 242, 228, 255),
       stroke_width=2, stroke_fill=(60, 38, 22, 200))
d.text((cx - en_w / 2, cy + 34), W_en, font=f_en, fill=(245, 231, 208, 255),
       stroke_width=1, stroke_fill=(60, 38, 22, 160))

shadow = tmp.filter(ImageFilter.GaussianBlur(6))
shadow.putalpha(shadow.getchannel("A").point(lambda a: int(a * 0.55)))

angle = -6.0           # 木饰面向右下倾斜，文字顺时针转 6°
rot = tmp.rotate(angle, resample=Image.BICUBIC, expand=True)
rot_sh = shadow.rotate(angle, resample=Image.BICUBIC, expand=True)

anchor = (830, 388)    # 木饰面中部
im.paste(Image.alpha_composite(
    Image.new("RGBA", im.size, (0, 0, 0, 0)),
    Image.new("RGBA", im.size, (0, 0, 0, 0))
), (0, 0), Image.new("RGBA", im.size, (0, 0, 0, 0)))

base = im.convert("RGBA")
for layer, dx in ((rot_sh, -2), (rot, 0)):
    base.alpha_composite(layer, (anchor[0] - rot.size[0] // 2 + dx, anchor[1] - rot.size[1] // 2))

# ---------- slogan：底部铺装区 ----------
f_sl = ImageFont.truetype(FONT_CN, 40)
band = Image.new("RGBA", (W, 90), (0, 0, 0, 0))
d = ImageDraw.Draw(band)
sl_w = d.textlength(W_slogan, font=f_sl)
d.text(((W - sl_w) / 2, 22), W_slogan, font=f_sl, fill=(255, 246, 232, 235),
       stroke_width=2, stroke_fill=(70, 45, 25, 170))
base.alpha_composite(band, (0, 985))

out = base.convert("RGB")
out.save(PREVIEW)
print("preview saved", PREVIEW, out.size)
