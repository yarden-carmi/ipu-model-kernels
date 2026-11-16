import torch

def reference(**kw):
    ids = kw['in0'].reshape(kw['s0_tokens'], 1).float()
    ramp = torch.arange(kw['s0_vocab'], device=ids.device).float()[None, :]
    decoded = (1 - (ids-ramp).abs()).clamp_min(0).double()
    x = decoded @ kw['w'] + kw['add']
    mu = x.mean(-1, keepdim=True)
    var = ((x-mu)**2).mean(-1, keepdim=True)
    y = (x-mu) / (var+kw['s2_eps']).sqrt()
    return {'out0': (y * kw['gamma'] + kw['beta']).reshape(1,kw['s2_rows'],kw['s2_channels'])}
