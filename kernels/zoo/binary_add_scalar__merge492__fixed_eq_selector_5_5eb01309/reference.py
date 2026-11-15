import torch

def reference(**kw):
    ids = kw['in0'].reshape(-1)[:kw['s0_numel']] + kw['scalar'].reshape(-1)[0]
    ids = ids - (ids == 492).to(ids.dtype)
    sel = (ids[:, None] == torch.arange(kw['s2_vocab'], device=ids.device)).double()
    first = sel @ kw['w']
    selected = first[:, kw['s4_sel'] if kw['s4_sel'] < 16 else 0]
    second = (selected[:, None] == torch.arange(kw['s5_vocab'], device=ids.device)).double() @ kw['v']
    return {'out0': first.unsqueeze(0), 'out1': second.unsqueeze(0)}
