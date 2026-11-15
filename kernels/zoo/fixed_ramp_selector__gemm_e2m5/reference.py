import torch


def reference(**kw):
    x = kw['in0'].reshape(kw['s0_tokens'], 1)
    ramp = torch.arange(kw['s0_vocab'], device=x.device).reshape(1, -1)
    indicators = (x == ramp).to(torch.float64)
    result = indicators @ kw['w']
    return {'out0': result.reshape(1, kw['s1_m'], kw['s1_n'])}
