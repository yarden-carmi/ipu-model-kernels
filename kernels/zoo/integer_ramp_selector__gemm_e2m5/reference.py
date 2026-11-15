import torch

def reference(**kw):
    ids = kw['in0'].reshape(-1).to(torch.int64)
    ramp = torch.arange(kw['s0_vocab'], device=ids.device)
    selector = (1 - (ids[:, None] - ramp[None, :]).abs()).clamp_min(0).float()
    return {'out0': (selector.double() @ kw['w']).reshape(1, kw['s1_m'], kw['s1_n'])}
