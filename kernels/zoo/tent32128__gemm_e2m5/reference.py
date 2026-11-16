import torch

def reference(**kw):
    ids = kw['in0'].reshape(kw['s0_tokens'], 1).to(torch.float32)
    ramp = torch.arange(kw['s0_vocab'], device=ids.device, dtype=torch.float32).reshape(1, -1)
    decoded = (1.0 - (ids - ramp).abs()).clamp_min(0.0)
    return {'out0': (decoded.to(torch.float64) @ kw['w']).reshape(1, kw['s1_m'], kw['s1_n'])}
