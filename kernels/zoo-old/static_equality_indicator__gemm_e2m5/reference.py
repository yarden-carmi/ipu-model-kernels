import torch

def reference(**kw):
    ids = kw['in0'].reshape(kw['s0_tokens'], 1).to(torch.int64)
    labels = torch.arange(kw['s0_vocab'], device=ids.device).reshape(1, -1)
    y = (ids == labels).float() @ kw['w'].float()
    if kw['s1_bias']:
        y = y + kw['bias'].float()
    return {'out0': y.unsqueeze(0)}
