from PIL import Image
import numpy as np
src = np.asarray(Image.open(r'doc/TF卡/bmp/好图/菜单图_v2/成品_clean/PIC1.bmp').convert('RGB').resize((640,480), Image.LANCZOS)).astype(np.uint16)
x0, y0 = 10, 63
crop = src[y0:y0+240, x0:x0+320].astype(np.uint16)
near = np.repeat(np.repeat(crop, 2, axis=0), 2, axis=1)
r = crop
h_even = r
h_odd  = (r + np.roll(r, -1, axis=1)) // 2
h = np.empty((240, 640, 3), dtype=np.uint16)
h[:, 0::2, :] = h_even
h[:, 1::2, :] = h_odd
h[:, 638:640, :] = h[:, 636:638, :]
v_top = h
v_bot = (h[:-1, :, :] + h[1:, :, :]) // 2
out = np.empty((480, 640, 3), dtype=np.uint16)
out[0:478:2, :, :] = v_top[0:239, :, :]
out[1:479:2, :, :] = v_bot[0:239, :, :]
out[478:480, :, :] = v_top[238:239, :, :]
cmp = np.concatenate([near.astype(np.uint8), out.astype(np.uint8)], axis=0)
Image.fromarray(cmp).save(r'sim\work_zoom\bilinear_compare.png')
Image.fromarray(out.astype(np.uint8)).save(r'sim\work_zoom\bilinear_left.png')
print('ok')
