import torch

def reference(**kw):
    x = kw['in0'].reshape(kw['s0_tokens'], 1).to(torch.int64)
    j = torch.arange(kw['s0_vocab'], device=x.device).reshape(1, -1)
    sel = (1 - (x - j).abs().clamp(max=1)).double()
    y = sel @ kw['w']
    y = y * torch.rsqrt(y.square().mean(dim=1, keepdim=True) + kw['s2_eps']) * kw['gamma']
    return {'out0': y.reshape(1, kw['s2_rows'], kw['s2_channels'])}
