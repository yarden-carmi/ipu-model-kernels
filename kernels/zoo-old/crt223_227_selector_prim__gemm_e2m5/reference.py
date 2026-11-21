import torch

def reference(**kw):
    ids = kw['in0'].reshape(-1, 1).to(torch.int64)
    rows = torch.arange(kw['s0_vocab'], device=ids.device).reshape(1, -1)
    selector = ((ids.remainder(223) == rows.remainder(223)) &
                (ids.remainder(227) == rows.remainder(227))).double()
    return {'out0': (selector @ kw['w']).reshape(1, kw['s1_m'], kw['s1_n'])}
