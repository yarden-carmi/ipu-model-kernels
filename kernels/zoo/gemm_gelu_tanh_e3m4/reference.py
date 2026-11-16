import torch

def reference(**kw):
    k, n = kw['k'], kw['n']
    y = kw['in0'].reshape(256, k) @ kw['w'].reshape(k, n)
    if kw['bias']:
        y = y + kw['b']
    return {'out0': torch.nn.functional.gelu(y, approximate='tanh').reshape(1, 256, n)}
