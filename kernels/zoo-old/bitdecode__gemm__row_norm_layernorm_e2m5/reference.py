import torch

def reference(**kw):
    ids = kw['in0'].reshape(-1).to(torch.int64)
    ramp = torch.arange(kw['s0_vocab'], device=ids.device, dtype=torch.int64)
    sel = torch.ones((ids.numel(), kw['s0_vocab']), dtype=torch.float64, device=ids.device)
    for bit in range((kw['s0_vocab'] - 1).bit_length()):
        sel *= 1 - (((ids[:, None] >> bit) ^ (ramp[None, :] >> bit)) & 1)
    x = sel @ kw['weights']
    x = x + kw['add0'].reshape_as(x) + kw['add1'].reshape_as(x)
    mu = x.mean(-1, keepdim=True)
    var = ((x-mu)**2).mean(-1, keepdim=True)
    y = (x-mu) * torch.rsqrt(var+kw['s2_eps'])
    return {'out0': (y*kw['gamma']+kw['beta']).reshape(1,kw['s2_rows'],kw['s2_channels'])}
