import torch

def reference(**kw):
    ids = kw['in0'].reshape(kw['s0_tokens']).to(torch.int64)
    j = torch.arange(kw['s0_vocab'], device=ids.device)
    mask = torch.ones((kw['s0_tokens'], kw['s0_vocab']), dtype=torch.bool, device=ids.device)
    for b in range((kw['s0_vocab'] - 1).bit_length()):
        mask &= (((ids[:, None] >> b) & 1) == ((j[None, :] >> b) & 1))
    return {'out0': (mask.double() @ kw['w']).reshape(1, kw['s1_m'], kw['s1_n'])}
