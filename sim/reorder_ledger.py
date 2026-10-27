import io
p = r'doc/项目进度.md'
lines = io.open(p, encoding='utf-8').read().split('\n')
i_fb = next(i for i,l in enumerate(lines) if l.startswith('### 封版'))
i_jl = next(i for i,l in enumerate(lines) if l.startswith('### 结案'))
i_e19 = next(i for i,l in enumerate(lines) if l.startswith('### 稳定点 E19.19'))
A = lines[:i_fb]
B = lines[i_fb:i_jl]
C = lines[i_jl:i_e19]
rest = lines[i_e19:]
out = B + C + A + rest
io.open(p,'w',encoding='utf-8',newline='').write('\n'.join(out))
print('moved; new head:', out[0][:40])
