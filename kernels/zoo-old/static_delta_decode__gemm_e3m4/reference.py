import torch

def reference(**kw):
    ids = kw['in0'].reshape(-1).to(torch.int64)
    ramp = torch.arange(kw['s0_vocab'], device=ids.device)
    decoded = (ids[:, None] == ramp[None, :]).double()
    return {'out0': (decoded @ kw['w']).reshape(1, kw['s1_m'], kw['s1_n'])}
