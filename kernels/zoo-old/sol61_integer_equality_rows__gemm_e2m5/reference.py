import torch

def reference(**kw):
    ids = kw['in0'].reshape(kw['s0_tokens']).to(torch.int64)
    coords = torch.arange(kw['s0_vocab'], device=ids.device)
    indicators = (ids[:, None] == coords[None, :]).to(torch.float32)
    return {'out0': (indicators.double() @ kw['w']).reshape(1, kw['s1_m'], kw['s1_n'])}
