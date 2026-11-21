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
    a=rounded((1-(x-j).abs()).clamp_min(0).double()@kw['w0'])
    ids=kw['in1'].reshape(-1).float()+1
    ids=torch.where(ids==468,ids-1,ids)
    j=torch.arange(kw['s4_vocab']).float()[None,:]
    b=rounded((1-(ids[:,None]-j).abs()).clamp_min(0).double()@kw['w1'])
    c=(b[:,:1]==0).double()@kw['v']
    z=rounded(rounded(a+b)+c)
    mu=z.mean(-1,keepdim=True)
    var=((z-mu)**2).mean(-1,keepdim=True)
    return {'out0':(((z-mu)*torch.rsqrt(var+kw['s11_eps']))*kw['gamma']+kw['beta']).unsqueeze(0)}
