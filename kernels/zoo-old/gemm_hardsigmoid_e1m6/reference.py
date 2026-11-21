import torch

def reference(**kw):
    m, k, n = kw['m'], kw['k'], kw['n']
    y = kw['in0'].reshape(m, -1)[:, :k] @ kw['w'][:, :n]
    if kw['bias']:
        y = y + kw['bias_vec'].reshape(-1)[:n]
    out = torch.zeros((m, ((n + 127) // 128) * 128), dtype=y.dtype)
    out[:, :n] = torch.clamp(y / 6 + 0.5, 0, 1)
    return {'out0': out}
