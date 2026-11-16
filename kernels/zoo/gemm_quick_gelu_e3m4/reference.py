import torch

def reference(**kw):
    m, k, n = kw['m'], kw['k'], kw['n']
    x = kw['in0'].reshape(m, k)
    w = kw['w'].reshape(k, n)
    y = x @ w
    if kw['bias']:
        y = y + kw['b']
    return {'out0': (y * torch.sigmoid(1.702 * y)).reshape(1, m, n)}
