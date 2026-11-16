import torch
import torch.nn.functional as F

def rounded(x):
    r = x.float().reshape(-1, 128).double()
    a = r.abs()
    e = torch.floor(torch.log2(a.clamp_min(2.0 ** -126)))
    scale = e.max(dim=-1, keepdim=True).values
    step = torch.pow(2.0, torch.maximum(e, scale - 2) - 5)
    y = torch.floor(a / step + 0.5) * step
    y = torch.minimum(y, torch.pow(2.0, scale) * (2 - 1 / 32))
    return (y * r.sign()).reshape(x.shape)

def reference(**kw):
    m, k, n = (int(kw[t]) for t in ('s0_m', 's0_k', 's0_n'))
    h, w = kw['s1_h'], kw['s1_w']
    a = kw['in0'].reshape(m, 128)[:, :k] @ kw['w0'][:k, :n]
    if kw['s0_bias']:
        a = a + kw['w0'][k, :n]
    row = torch.zeros(m, 128, dtype=torch.float64)
    row[:, :n] = F.silu(a)
    x = rounded(row)[:, :n].reshape(h, w, n).permute(2, 0, 1)[None]
    c = kw['s1_cout']
    weights = kw['w1'][:9, :c].T.reshape(c, 1, 3, 3)
    bias = kw['w1'][9, :c] if kw['s1_bias'] else None
    y = F.silu(F.conv2d(x, weights, bias, padding=kw['s1_padding'], stride=kw['s1_stride'], groups=kw['s1_groups']))
    out = torch.zeros(h*w, 128, dtype=torch.float64)
    out[:, :c] = y[0].permute(1, 2, 0).reshape(-1, c)
    return {'out0': out}
