import torch

def reference(**kw):
    ids = kw['in0'].reshape(kw['s0_tokens']).to(torch.int64)
    ramp = torch.arange(kw['s0_vocab'], device=ids.device)
    hat = (1 - (ids[:, None] - ramp[None, :]).abs()).clamp_min(0).double()
    return {'out0': (hat @ kw['w']).reshape(1, kw['s1_m'], kw['s1_n'])}
