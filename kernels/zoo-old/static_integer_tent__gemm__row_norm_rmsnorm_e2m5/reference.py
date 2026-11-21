import torch

def reference(**kw):
    ids = kw['in0'].reshape(kw['s0_tokens'], 1).to(torch.int64)
    ramp = torch.arange(kw['s0_vocab'], device=ids.device).reshape(1, -1)
    indicators = (1 - (ids - ramp).abs()).clamp_min(0).double()
    x = indicators @ kw['w']
    if kw['s1_bias']:
        x = x + kw['bias']
    y = x * torch.rsqrt(x.square().mean(-1, keepdim=True) + kw['s2_eps']) * kw['gamma']
    return {'out0': y.reshape(1, kw['s2_rows'], kw['s2_channels'])}
