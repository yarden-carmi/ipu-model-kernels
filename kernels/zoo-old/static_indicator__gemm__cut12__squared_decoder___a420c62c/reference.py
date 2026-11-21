import torch

def rounded(x):
    shape = x.shape
    r = x.float().reshape(-1, 128).double()
    a = r.abs()
    e = torch.floor(torch.log2(a.clamp_min(2.0**-126)))
    scale = e.max(-1, keepdim=True).values
    step = 2.0**(torch.maximum(e, scale-2)-5)
    y = torch.minimum(torch.floor(a/step+0.5)*step, 2.0**scale*(2-1/32))
    return (y*r.sign()).reshape(shape)

def reference(**kw):
    ids = kw['in0'].reshape(-1).long()
    labels = torch.arange(kw['s0_vocab'], device=ids.device)
    x = rounded((ids[:, None] == labels).double() @ kw['w'])
    # Replication is independent of the cut12/decoder/scan input values.
    t = kw['table'].reshape(1, kw['s6_dim']).expand(kw['s6_tokens'], -1)
    x = rounded(x + t)
    x = rounded(x + t)
    mu = x.mean(-1, keepdim=True)
    y = (x-mu)*torch.rsqrt(((x-mu)**2).mean(-1, keepdim=True)+kw['s9_eps'])
    y = y*kw['gamma']+kw['beta']
    return {'out0': y.T.contiguous().reshape(kw['s9_channels'], 1, kw['s9_rows'])}
