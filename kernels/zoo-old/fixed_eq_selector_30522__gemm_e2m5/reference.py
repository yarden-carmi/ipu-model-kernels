import torch

def reference(**kw):
    x = kw['in0'].reshape(-1, 1)
    ramp = torch.arange(kw['s0_vocab'], device=x.device).reshape(1, -1)
    selector = (x == ramp).to(torch.float64)
    return {'out0': (selector @ kw['w']).reshape(1, kw['s1_m'], kw['s1_n'])}
