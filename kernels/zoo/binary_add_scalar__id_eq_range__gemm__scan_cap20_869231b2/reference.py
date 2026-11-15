import torch

def reference(**kw):
    ids = kw['in0'].reshape(-1)[:kw['s0_numel']] + kw['scalar'].reshape(-1)[0]
    ramp = torch.arange(kw['s1_vocab'], device=ids.device)
    selector = (ids[:, None] == ramp[None, :]).double()
    first = selector @ kw['w']
    scanned = first[:, kw['s3_sel']]
    second = (scanned.to(torch.int64) == 0).double()[:, None] @ kw['v']
    return {'out0': first.unsqueeze(0), 'out1': second.unsqueeze(0)}
