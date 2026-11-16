import torch

def reference(**kw):
    ids = kw['in0'].reshape(-1, 1)
    selector = (ids == torch.arange(kw['s0_vocab'], device=ids.device).reshape(1, -1)).double()
    return {'out0': (selector @ kw['w']).reshape(1, kw['s1_m'], kw['s1_n'])}
