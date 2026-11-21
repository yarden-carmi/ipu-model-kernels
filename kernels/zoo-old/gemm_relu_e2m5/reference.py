import torch

def reference(**kw):
    m, k, n = (int(kw[t]) for t in ('m', 'k', 'n'))
    y = kw['in0'].reshape(m, k) @ kw['w'].reshape(k, n)
    if kw['bias']:
        y = y + kw['b']
    return {'out0': torch.relu(y).reshape(1, m, n)}
