import torch


def reference(**kw):
    ids = kw['in0'].reshape(-1).to(torch.int64)
    ramp = torch.arange(kw['s0_vocab'], device=ids.device)
    decoded = (ids[:, None] == ramp[None, :]).to(torch.float64)
    x = decoded @ kw['w'].reshape(kw['s1_k'], kw['s1_n'])
    x = x + kw['add0'].reshape(kw['s1_m'], kw['s1_n'])
    x = x + kw['add1'].reshape(kw['s1_m'], kw['s1_n'])
    mean = x.mean(dim=-1, keepdim=True)
    var = ((x - mean) ** 2).mean(dim=-1, keepdim=True)
    y = (x - mean) * torch.rsqrt(var + kw['s2_eps'])
    y = y * kw['gamma'].reshape(1, -1) + kw['beta'].reshape(1, -1)
    return {'out0': y.reshape(1, kw['s2_rows'], kw['s2_channels'])}
