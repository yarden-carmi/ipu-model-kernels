import torch

def reference(**kw):
    m, k, n = kw['m'], kw['k'], kw['n']
    x = kw['in0'].reshape(m, -1)[:, :k]
    w = kw['w'].reshape(k, 128)[:, :n]
    y = x @ w
    if kw['bias']:
        y = y + kw['b'][:n]
    out = torch.zeros(m, 128, dtype=torch.float64)
    out[:, :n] = y
    return {'out0': out}
