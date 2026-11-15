import torch

def reference(**kw):
    t, v = kw['s0_tokens'], kw['s0_vocab']
    d = kw['in0'].reshape(t, 1).to(torch.int64) - torch.arange(v).reshape(1, -1)
    h = (1 - d.abs().clamp(max=1)).to(torch.float64)
    x = h @ kw['w'].reshape(kw['s1_k'], kw['s1_n'])
    x = x + kw['add0'].reshape_as(x) + kw['add1'].reshape_as(x)
    mu = x.mean(-1, keepdim=True)
    var = ((x - mu)**2).mean(-1, keepdim=True)
    y = (x-mu) / torch.sqrt(var + kw['s2_eps'])
    y = y * kw['gamma'] + kw['beta']
    return {'out0': y.reshape(1, kw['s2_rows'], kw['s2_channels'])}
