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
    m, k, n = (int(kw[t]) for t in ('s1_m', 's1_k', 's1_n'))
    h, w = kw['s2_h'], kw['s2_w']
    nb = (n + 127) // 128
    s = torch.zeros(m, 128, dtype=torch.float64)
    s[:, :k] = (kw['in0'] + kw['in1']).reshape(m, 128)[:, :k]
    x = rounded(s)
    w0 = kw['w0'].reshape(nb, k + 1, 128).permute(1, 0, 2).reshape(k + 1, nb * 128)[:, :n]
    a = x[:, :k] @ w0[:k, :n]
    if kw['s1_bias']:
        a = a + w0[k, :n]
    row = torch.zeros(m, nb * 128, dtype=torch.float64)
    row[:, :n] = F.silu(a)
    x = rounded(row)[:, :n].reshape(h, w, n).permute(2, 0, 1)[None]
    c = kw['s2_cout']
    w1 = kw['w1'].reshape(nb, 10, 128).permute(1, 0, 2).reshape(10, nb * 128)[:, :c]
    y = F.silu(F.conv2d(x, w1[:9].T.reshape(c, 1, 3, 3), w1[9] if kw['s2_bias'] else None, padding=kw['s2_padding'], stride=kw['s2_stride'], groups=kw['s2_groups']))
    out = torch.zeros(h*w, nb * 128, dtype=torch.float64)
    out[:, :c] = y[0].permute(1, 2, 0).reshape(-1, c)
    return {'out0': s, 'out1': out.reshape(-1, 128)}
