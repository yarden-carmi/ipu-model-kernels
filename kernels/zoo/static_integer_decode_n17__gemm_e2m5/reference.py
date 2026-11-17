import torch

def reference(**kw):
    ids = kw['in0'].reshape(kw['s0_tokens'], 1).to(torch.int64)
    labels = torch.arange(kw['s0_vocab'], device=ids.device)
    decoded = (ids == labels.reshape(1, -1)).to(torch.float64)
    y = decoded @ kw['w']
    if kw['s1_bias']:
        y = y + kw['b']
    return {'out0': y.reshape(1, kw['s1_m'], kw['s1_n'])}
