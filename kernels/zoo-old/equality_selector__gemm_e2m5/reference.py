import torch
def reference(**kw):
    ids = kw['in0'].reshape(kw['s0_tokens'], 1)
    ramp = torch.arange(kw['s0_vocab'], device=ids.device).reshape(1, -1)
    return {'out0': ((ids == ramp).double() @ kw['w']).reshape(1, kw['s1_m'], kw['s1_n'])}
