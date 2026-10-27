from PIL import Image, ImageDraw
im = Image.open(r'doc/TF卡/bmp/好图/菜单图_v2/成品_clean/PIC1.bmp').convert('RGB').resize((640,480), Image.LANCZOS)
d = ImageDraw.Draw(im)
for x in range(0,640,40):
    d.line([(x,0),(x,480)], fill=(255,0,0), width=1)
for y in range(0,480,40):
    d.line([(0,y),(640,y)], fill=(0,120,255), width=1)
im.save(r'sim\work_zoom\grid_pic1.png')
print('ok')
