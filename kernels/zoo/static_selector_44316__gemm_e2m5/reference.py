import torch

def reference(**kw):
    ids = kw['in0'].reshape(-1)[:kw['s0_tokens']].to(torch.int64)
    ramp = torch.arange(kw['s0_vocab'], device=ids.device)
    selector = (ids[:, None] == ramp[None, :]).to(torch.float64)
    result = selector @ kw['w']
    return {'out0': result.reshape(1, kw['s1_m'], kw['s1_n'])}
