import torch

def reference(**kw):
    ids = kw['in0'].reshape(kw['s0_tokens'])
    selector = (ids[:, None] == torch.arange(kw['s0_vocab'], device=ids.device)[None, :]).double()
    return {'out0': (selector @ kw['w']).reshape(1, kw['s1_m'], kw['s1_n'])}
