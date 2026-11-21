import torch

def reference(**kw):
    ids = kw['in0'].reshape(kw['s0_tokens'], 1).to(torch.int64)
    ramp = torch.arange(kw['s0_vocab'], device=ids.device).reshape(1, -1)
    indicators = (1 - (ids - ramp).abs()).clamp_min(0).to(torch.float64)
    return {'out0': (indicators @ kw['w']).reshape(1, kw['s1_m'], kw['s1_n'])}
