import torch
def reference(**kw):
    x = kw['in0'].reshape(-1, 1)
    d = x - torch.arange(kw['s0_vocab'], dtype=x.dtype, device=x.device)
    a = torch.relu(1 - torch.relu(d) - torch.relu(-d)) @ kw['w']
    mu = a.mean(-1, keepdim=True)
    var = ((a - mu)**2).mean(-1, keepdim=True)
    y = (a-mu) / torch.sqrt(var + kw['s2_eps']) * kw['gamma'] + kw['beta']
    return {'out0': y.reshape(1, kw['s2_rows'], kw['s2_channels'])}
