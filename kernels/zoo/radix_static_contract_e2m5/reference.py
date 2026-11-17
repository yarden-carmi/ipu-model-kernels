import torch

def reference(**kw):
    ids = kw['in0'].reshape(-1).long()
    table = kw['table']
    # Both radix predicates jointly select exactly one static table row.
    labels = torch.arange(kw['vocab'], device=ids.device)
    lo = ids[:, None].remainder(512) == labels[None, :].remainder(512)
    hi = torch.div(ids[:, None], 512, rounding_mode='floor') == labels[None, :] // 512
    return {'out0': ((lo & hi).double() @ table).reshape(1, kw['tokens'], kw['dim'])}
