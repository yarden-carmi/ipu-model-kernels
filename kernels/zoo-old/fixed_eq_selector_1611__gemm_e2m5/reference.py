import torch

def reference(**kw):
    x = kw['in0'].reshape(-1)
    indicators = (x[:, None] == torch.arange(kw['s0_vocab'], device=x.device)[None, :]).double()
    y = indicators @ kw['w']
    if kw['s1_bias']:
        y = y + kw['b']
    return {'out0': y.reshape(1, kw['s1_m'], kw['s1_n'])}
