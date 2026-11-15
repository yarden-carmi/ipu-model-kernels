import torch

def reference(**kw):
    ids = kw['in0'].reshape(-1)[:kw['s0_numel']] + kw['scalar'].reshape(-1)[0]
    ids = torch.where(ids == 8191, 8190, ids)
    sel = (ids[:, None] == torch.arange(kw['s2_vocab'], device=ids.device)[None, :]).double()
    first = sel @ kw['w']
    second = (first[:, 0:1] == 0).double() @ kw['v']
    return {'out0': first.unsqueeze(0), 'out1': second.unsqueeze(0)}
