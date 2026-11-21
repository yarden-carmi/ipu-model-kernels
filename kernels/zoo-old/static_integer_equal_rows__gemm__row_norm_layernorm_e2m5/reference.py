import torch

def reference(**kw):
    ids = kw['in0'].reshape(-1).to(torch.int64)
    sel = (ids[:, None] == torch.arange(kw['s0_vocab'], device=ids.device)[None, :]).double()
    x = sel @ kw['w']
    mean = x.mean(-1, keepdim=True)
    var = ((x - mean)**2).mean(-1, keepdim=True)
    y = (x - mean) * torch.rsqrt(var + kw['s2_eps']) * kw['gamma'] + kw['beta']
    return {'out0': y.reshape(1, kw['s2_rows'], kw['s2_channels'])}
