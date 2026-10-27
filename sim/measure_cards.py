from PIL import Image
import numpy as np
im = Image.open(r'doc/TF卡/bmp/好图/菜单图_v2/成品_clean/PIC1.bmp').convert('RGB').resize((640,480), Image.LANCZOS)
a = np.asarray(im).astype(int)
white = (a[:,:,0]>200)&(a[:,:,1]>195)&(a[:,:,2]>185)
colsum = white.sum(axis=0); rowsum = white.sum(axis=1)
cols = [i for i,v in enumerate(colsum) if v>60]
rows = [i for i,v in enumerate(rowsum) if v>60]
def runs(idx):
    out=[]; s=idx[0]; p=idx[0]
    for i in idx[1:]:
        if i!=p+1: out.append((s,p)); s=i
        p=i
    out.append((s,p)); return out
print('col runs', runs(cols)[:6])
print('row runs', runs(rows)[:6])
