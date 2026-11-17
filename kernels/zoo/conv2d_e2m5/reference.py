import torch
import torch.nn.functional as F

def reference(**kw):
    ci, co, h, w, kh, kx = [int(kw[k]) for k in ('cin', 'cout', 'h', 'w', 'kh', 'kw')]
    x = kw['in0'][..., :ci].permute(2, 0, 1).unsqueeze(0)
    rows = kw['weights'].reshape(co // 128, -1, 128)
    weight = rows[:, 1:].reshape(co // 128, kh, kx, ci, 128).permute(0, 4, 3, 1, 2).reshape(co, ci, kh, kx)
    b = rows[:, 0].reshape(co) if kw['bias'] else None
    y = F.conv2d(x, weight, b, stride=kw['stride'], padding=kw['padding'], groups=kw['groups'])
    return {'out0': F.pad(y.flatten(2).transpose(1, 2), (0, 0, 0, 101))}
