import torch

def reference(**kw):
    x = kw['in0'].reshape(-1, 1)
    sel = (x == torch.arange(kw['s0_vocab'], device=x.device).reshape(1, -1)).double()
    y = sel @ kw['w']
    mu = y.mean(-1, keepdim=True)
    var = ((y-mu)**2).mean(-1, keepdim=True)
    y = (y-mu) / torch.sqrt(var + kw['s2_eps'])
    return {'out0': (y * kw['gamma'] + kw['beta']).reshape(1, kw['s2_rows'], kw['s2_channels'])}
