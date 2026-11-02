"""生成 16:9 测试图：内容铺满 1280x720（不含内嵌黑边），用来验证 FPGA 的等比缩放+留边。

注意：图片本身必须是"满幅 16:9"，黑边要由 FPGA 加出来才有说服力。
"""
from PIL import Image, ImageDraw, ImageFont

SRC = r"D:\AAA_University\Anlu\Project\doc\TF卡\bmp\好图\咖啡店面图_v2.png"
OUT = r"D:\AAA_University\Anlu\Project\doc\TF卡\bmp\好图\菜单图_v3_封面\PIC2_16x9_测试.BMP"
PREVIEW = r"D:\AAA_University\Anlu\Project\sim\diag_covers\preview_16x9.png"

W, H = 1280, 720

im = Image.open(SRC).convert("RGB")
# 原图 1448x1086 -> 取 16:9 最大内接：高 1086 对应宽 1086*16/9 = 1930 > 1448，故按宽裁高
crop_w = im.width
crop_h = int(crop_w * 9 / 16)          # 1448*9/16 = 814
top = (im.height - crop_h) // 2
im = im.crop((0, top, crop_w, top + crop_h)).resize((W, H), Image.LANCZOS)

d = ImageDraw.Draw(im)
font = ImageFont.truetype(r"C:\Windows\Fonts\msyhbd.ttc", 64)
font2 = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 40)
d.text((40, 40), "16:9 测试图 1280x720", font=font, fill=(255, 255, 255))
d.text((40, 130), "若屏幕上出现上下黑边，说明 FPGA 做了等比缩放", font=font2, fill=(255, 255, 255))
d.rectangle([0, 0, W - 1, H - 1], outline=(255, 60, 60), width=6)

im.save(OUT, format="BMP")
im.save(PREVIEW)
print("生成:", OUT, im.size)
