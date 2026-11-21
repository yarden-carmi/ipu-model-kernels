import torch

def reference(**kw):
    ids = kw['in0'].reshape(-1).long()
    x = kw['w'][ids]
    if kw['s1_bias']:
        x = x + kw['bias']
    y = x * torch.rsqrt(x.square().mean(-1, keepdim=True) + kw['s2_eps'])
    return {'out0': (y * kw['gamma']).reshape(1, kw['s2_rows'], kw['s2_channels'])}
