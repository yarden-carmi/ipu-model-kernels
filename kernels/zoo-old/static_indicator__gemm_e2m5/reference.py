import torch

def reference(**kw):
    ids = kw['in0'].reshape(kw['s0_tokens']).to(torch.int64)
    labels = torch.arange(kw['s0_vocab'], device=ids.device)
    indicator = (ids[:, None] == labels[None, :]).double()
    return {'out0': (indicator @ kw['w']).reshape(1, kw['s1_m'], kw['s1_n'])}
