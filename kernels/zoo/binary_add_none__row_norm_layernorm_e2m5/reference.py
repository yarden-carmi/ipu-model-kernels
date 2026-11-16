import torch

def rounded(x):
    r = x.float().reshape(-1,128).double()
    a = r.abs()
    e = torch.floor(torch.log2(a.clamp_min(2.0**-126)))
    scale = e.max(-1,keepdim=True).values
    step = 2.0**(torch.maximum(e,scale-2)-5)
    y = torch.minimum(torch.floor(a/step+0.5)*step, 2.0**scale*(2-1/32))
    return (y*r.sign()).reshape(x.shape)

def reference(**kw):
    r,c = kw['s1_rows'],kw['s1_channels']
    n = kw['s0_numel']
    x = kw['in0'].reshape(-1)[:n].reshape(r,c) + kw['operand'].reshape(r,c)
    z = rounded(x)
    mu = z.mean(-1,keepdim=True)
    y = (z-mu)*torch.rsqrt(((z-mu)**2).mean(-1,keepdim=True)+kw['s1_eps'])
    y = y*kw['gamma']+kw['beta']
    return {'out0':x.reshape(1,r,c),'out1':y.reshape(1,r,c)}
