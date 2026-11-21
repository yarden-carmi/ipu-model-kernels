import torch

def reference(**kw):
    x = kw['in0'].reshape(kw['s0_tokens'], 1)
    labels = torch.arange(kw['s0_vocab'], device=x.device, dtype=x.dtype)
    d = x - labels
    selectors = torch.relu(1 - (torch.relu(d) + torch.relu(-d)))
    return {'out0': (selectors @ kw['w']).reshape(1, kw['s1_m'], kw['s1_n'])}
