import torch


def rounded(x):
    r = x.float().reshape(-1, 128).double()
    a = r.abs()
    e = torch.floor(torch.log2(a.clamp_min(2.0**-126)))
    scale = e.max(-1, keepdim=True).values
    step = 2.0**(torch.maximum(e, scale - 2) - 5)
    y = torch.minimum(torch.floor(a / step + 0.5) * step, 2.0**scale * (2 - 1 / 32))
    return (y * r.sign()).reshape(x.shape)


def reference(**kw):
    r, c = kw['s1_rows'], kw['s1_channels']
    z = rounded(kw['in0'] + kw['in1']).reshape(r, c)
    y = z * torch.rsqrt(z.square().mean(-1, keepdim=True) + kw['s1_eps'])
    return {'out0': (y * kw['gamma'].reshape(1, c)).reshape(1, r, c)}
