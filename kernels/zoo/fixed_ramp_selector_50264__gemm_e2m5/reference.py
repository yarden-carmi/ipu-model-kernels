import torch

def reference(**kw):
    ids = kw['in0'].reshape(-1).to(torch.int64)
    sel = (ids[:, None] == torch.arange(kw['s0_vocab'], device=ids.device)[None, :]).double()
    out = sel @ kw['w']
    return {'out0': out.reshape(1, kw['s1_m'], kw['s1_n'])}
