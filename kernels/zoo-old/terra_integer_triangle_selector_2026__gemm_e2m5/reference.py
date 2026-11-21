import torch
def reference(**kw):
    ids = kw['in0'].reshape(-1)[:kw['s0_tokens']].to(torch.int64)
    j = torch.arange(kw['s0_vocab'], device=ids.device, dtype=torch.int64)
    selector = (1 - (ids[:, None] - j[None, :]).abs()).clamp(min=0).to(torch.float64)
    return {'out0': (selector @ kw['w']).reshape(1, kw['s1_m'], kw['s1_n'])}
