import torch

def reference(**kw):
    x = kw['in0'].reshape(kw['s0_tokens'], 1).to(torch.float32)
    j = torch.arange(kw['s0_vocab'], device=x.device, dtype=torch.float32).reshape(1, -1)
    tent = (1.0 - (x - j).abs()).clamp_min(0.0)
    return {'out0': (tent.to(torch.float64) @ kw['w']).reshape(1, kw['s1_m'], kw['s1_n'])}
