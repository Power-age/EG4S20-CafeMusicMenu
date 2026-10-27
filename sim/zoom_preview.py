from PIL import Image
src = Image.open(r'doc/TF卡/bmp/好图/菜单图_v2/成品_clean/PIC1.bmp').convert('RGB').resize((640,480), Image.LANCZOS)
opts = [('A photo-centered', 10, 63), ('B photo-bottom', 10, 88)]
strip = Image.new('RGB', (640*2, 480*2), (0,0,0))
for i,(name,x0,y0) in enumerate(opts):
    L = src.crop((x0, y0, x0+320, y0+240)).resize((640,480), Image.NEAREST)
    R = src.crop((320, y0, 320+320, y0+240)).resize((640,480), Image.NEAREST)
    strip.paste(L, (i*640, 0))
    strip.paste(R, (i*640, 480))
strip.save(r'sim\work_zoom\zoom_options.png')
print('A: x0=10/320 y0=63  B: x0=10/320 y0=88')
