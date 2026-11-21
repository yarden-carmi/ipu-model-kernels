import torch

def rounded(x):
    r = x.float().reshape(-1, 128).double()
    a = r.abs()
    e = torch.floor(torch.log2(a.clamp_min(2.0**-126)))
    scale = e.max(-1, keepdim=True).values
    step = 2.0**(torch.maximum(e, scale-6)-4)
    y = torch.minimum(torch.floor(a/step+0.5)*step, 2.0**scale*(2-1/16))
    return (y*r.sign()).reshape(x.shape)

def reference(**kw):
    r, c = kw['s1_rows'], kw['s1_channels']
    n = r * c
    flat0 = kw['in0'].to(torch.float64).reshape(-1)
    flat0 = torch.cat([flat0, torch.zeros(n - flat0.numel(), dtype=torch.float64)])[:n]
    flat1 = kw['in1'].to(torch.float64).reshape(-1)
    flat1 = torch.cat([flat1, torch.zeros(n - flat1.numel(), dtype=torch.float64)])[:n]
    x = (flat0 + flat1).reshape(r, c)
    z = rounded(x)
    mu = z.mean(-1, keepdim=True)
    y = (z - mu) * torch.rsqrt(((z - mu) ** 2).mean(-1, keepdim=True) + kw['s1_eps'])
    gamma = kw['gamma'].to(torch.float64).reshape(-1)[:c]
    beta = kw['beta'].to(torch.float64).reshape(-1)[:c]
    y = y * gamma + beta
    return {'out0': y.reshape(1, r, c)}
