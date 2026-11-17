import torch

def rounded(x):
    r=x.float().reshape(-1,128).double()
    a=r.abs()
    e=torch.floor(torch.log2(a.clamp_min(2.0**-126)))
    scale=e.max(-1,keepdim=True).values
    step=2.0**(torch.maximum(e,scale-2)-5)
    y=torch.minimum(torch.floor(a/step+0.5)*step,2.0**scale*(2-1/32))
    return (y*r.sign()).reshape(x.shape)

def reference(**kw):
    x=kw['in0'].reshape(-1,1).float()
    j=torch.arange(kw['s0_vocab']).float()[None,:]
    z=(1-(x-j).abs()).clamp_min(0).double() @ kw['w']
    z=z.reshape(1,kw['s1_m'],kw['s1_n'])+kw['add']
    z=rounded(z)
    mu=z.mean(-1,keepdim=True)
    var=(z-mu).square().mean(-1,keepdim=True)
    y=(z-mu)*torch.rsqrt(var+kw['s2_eps'])*kw['gamma']+kw['beta']
    return {'out0':z,'out1':y}
