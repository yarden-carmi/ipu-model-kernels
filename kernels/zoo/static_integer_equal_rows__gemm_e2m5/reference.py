import torch

def reference(**kw):
    ids = kw['in0'].reshape(kw['s0_tokens']).to(torch.int64)
    ramp = torch.arange(kw['s0_vocab'], device=ids.device)
    selector = (ids[:, None] == ramp[None, :]).double()
    return {'out0': (selector @ kw['w']).reshape(1, kw['s1_m'], kw['s1_n'])}
