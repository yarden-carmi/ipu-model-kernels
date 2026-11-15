import torch

def reference(**kw):
    x = kw['in0'].reshape(-1, 1)
    selector = (x == torch.arange(kw['s0_vocab'], device=x.device).reshape(1, -1)).double()
    y = selector @ kw['w']
    y = y * torch.rsqrt(y.square().mean(dim=1, keepdim=True) + kw['s2_eps']) * (kw['gamma'] * 1024)
    return {'out0': y.reshape(1, kw['s2_rows'], kw['s2_channels'])}
