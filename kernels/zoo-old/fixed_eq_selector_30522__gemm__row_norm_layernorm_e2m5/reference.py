import torch


def reference(**kw):
    ids = kw['in0'].reshape(-1)[:kw['s0_tokens']]
    ramp = torch.arange(kw['s0_vocab'], device=ids.device)
    sel = (ids[:, None] == ramp[None, :]).to(torch.float64)
    x = sel @ kw['weights']
    x = x + kw['add0'].reshape_as(x) + kw['add1'].reshape_as(x)
    mu = x.mean(-1, keepdim=True)
    var = ((x - mu) ** 2).mean(-1, keepdim=True)
    y = (x - mu) * torch.rsqrt(var + kw['s2_eps'])
    y = y * kw['gamma'] + kw['beta']
    return {'out0': y.reshape(1, kw['s2_rows'], kw['s2_channels'])}
