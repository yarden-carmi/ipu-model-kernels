import torch
import torch.nn.functional as F


def reference(**kw):
    m, k, n = (int(kw[t]) for t in ('m', 'k', 'n'))
    pn = ((n + 127) // 128) * 128
    x = kw['in0'].reshape(m, -1)[:, :k]
    w = kw['w'].reshape(k, pn)[:, :n]
    y = x @ w
    if kw['bias']:
        y = y + kw['bias_vec'].reshape(-1)[:n]
    out = torch.zeros(m, pn, dtype=torch.float64)
    out[:, :n] = F.silu(y)
    return {'out0': out}
