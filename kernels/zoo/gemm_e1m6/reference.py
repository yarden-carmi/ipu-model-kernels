import torch

def reference(**kw):
    m, k, n = kw['m'], kw['k'], kw['n']
    no = ((n + 127) // 128) * 128
    x = kw['in0'].reshape(m, -1)[:, :k]
    w = kw['w'].reshape(-1, no)[:k, :n]
    y = x @ w
    if kw['bias']:
        y = y + kw['b'][:n]
    out = torch.zeros(m, no, dtype=torch.float64)
    out[:, :n] = y
    return {'out0': out.reshape(-1, 128)}
