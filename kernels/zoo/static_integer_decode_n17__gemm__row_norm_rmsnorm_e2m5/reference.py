import torch

def reference(**kw):
    ids = kw['in0'].reshape(kw['s0_tokens'], 1).to(torch.int64)
    labels = torch.arange(kw['s0_vocab'], device=ids.device)
    x = (ids == labels.reshape(1, -1)).double() @ kw['w']
    y = x * torch.rsqrt(x.square().mean(dim=-1, keepdim=True) + kw['s2_eps']) * kw['gamma']
    return {'out0': y.reshape(1, kw['s2_rows'], kw['s2_channels'])}
