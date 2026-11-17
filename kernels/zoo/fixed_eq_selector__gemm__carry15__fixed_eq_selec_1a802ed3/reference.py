import torch

def rounded(x):
    r = x.float().reshape(-1, 128).double()
    a = r.abs()
    e = torch.floor(torch.log2(a.clamp_min(2.0**-126)))
    scale = e.max(-1, keepdim=True).values
    step = 2.0**(torch.maximum(e, scale - 2) - 5)
    y = torch.minimum(torch.floor(a / step + 0.5) * step,
                      2.0**scale * (2 - 1 / 32))
    return (y * r.sign()).reshape(x.shape)

def reference(**kw):
    a = kw['in0'].reshape(-1, 1)
    a = (a == torch.arange(kw['s0_vocab']).reshape(1, -1)).double() @ kw['w0']
    x = kw['in1'].long().reshape(-1)
    y = torch.ones_like(x)
    for _ in range(15):
        x, y = x ^ y, (x & y) << 1
    b = (x[:, None] == torch.arange(kw['s3_vocab'])[None, :]).double() @ kw['w1']
    # blocked_mux's values are dead: the singleton selector is always one.
    c = torch.ones((kw['s6_tokens'], 1), dtype=torch.float64) @ kw['v']
    z = rounded(rounded(a + b) + c)
    mu = z.mean(-1, keepdim=True)
    var = ((z - mu)**2).mean(-1, keepdim=True)
    out = (z - mu) * torch.rsqrt(var + kw['s10_eps'])
    out = out * kw['gamma'] + kw['beta']
    return {'out0': out.unsqueeze(0)}
