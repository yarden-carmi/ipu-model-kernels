import torch
import torch.nn.functional as F

def reference(**kw):
    h, w, ci, co, kh, kx = (int(kw[k]) for k in ('h', 'w', 'cin', 'cout', 'kh', 'kw'))
    x = kw['in0'].reshape(h, w, ci).permute(2, 0, 1).unsqueeze(0)
    weight = kw['weights'].reshape(kh, kx, ci, co).permute(3, 2, 0, 1).contiguous()
    b = kw['bias_vec'].reshape(co) if kw['bias'] else None
    y = F.gelu(F.conv2d(x, weight, b, stride=kw['stride'], padding=kw['padding'], groups=kw['groups']))
    return {'out0': y[0].permute(1, 2, 0).contiguous()}
