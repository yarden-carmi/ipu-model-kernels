import torch

def reference(**kw):
    x = kw['in0'].reshape(-1, 1)
    sel = (x == torch.arange(kw['s0_vocab'], device=x.device).reshape(1, -1)).double()
    v = sel @ kw['w']
    y = v * torch.rsqrt(v.square().mean(1, keepdim=True) + kw['s2_eps']) * kw['gamma']
    y = torch.where(v == 0, torch.zeros_like(y), y)
    return {'out0': y.reshape(1, kw['s2_rows'], kw['s2_channels'])}
