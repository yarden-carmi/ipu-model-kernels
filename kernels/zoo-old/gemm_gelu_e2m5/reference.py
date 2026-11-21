import torch

def reference(**kw):
    m, k, n = kw['m'], kw['k'], kw['n']
    y = kw['in0'].reshape(m, k) @ kw['w'].reshape(k, n)
    if kw['bias']:
        y = y + kw['b']
    return {'out0': torch.nn.functional.gelu(y, approximate='none').reshape(1, m, n)}
