import torch

def reference(**kw):
    ids = kw['in0'].reshape(kw['s0_tokens']).to(torch.int64)
    j = torch.arange(kw['s0_vocab'], device=ids.device)
    selector = ((ids[:, None] // 512 == j[None, :] // 512) &
                (ids[:, None] % 512 == j[None, :] % 512)).double()
    out = selector @ kw['w']
    if kw['s1_bias']:
        out = out + kw['bias']
    return {'out0': out.reshape(1, kw['s1_m'], kw['s1_n'])}
