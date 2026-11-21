import torch
import torch.nn.functional as F

def rounded(x):
    r = x.float().reshape(-1, 128).double()
    a = r.abs()
    e = torch.floor(torch.log2(a.clamp_min(2.0 ** -126)))
    scale = e.max(-1, keepdim=True).values
    step = 2.0 ** (torch.maximum(e, scale - 2) - 5)
    y = torch.minimum(torch.floor(a / step + 0.5) * step, 2.0 ** scale * (2 - 1 / 32))
    return (y * r.sign()).reshape(x.shape)

def reference(**p):
    m, k, n = p['s1_m'], p['s1_k'], p['s1_n']
    x = (p['in0'] + p['in1'])[:, :k]
    out0 = torch.zeros(m, 128, dtype=torch.float64)
    out0[:, :k] = x
    x = rounded(out0)[:, :k]
    w = p['w'].permute(1, 0, 2).reshape(k, -1)[:, :n]
    y = x @ w
    if p['s1_bias']:
        y = y + p['b'].reshape(-1)[:n]
    out1 = torch.zeros(m, ((n + 127) // 128) * 128, dtype=torch.float64)
    out1[:, :n] = F.silu(y)
    return {'out0': out0, 'out1': out1}
