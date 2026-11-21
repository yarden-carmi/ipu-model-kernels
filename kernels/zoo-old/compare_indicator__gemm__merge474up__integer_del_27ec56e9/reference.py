import torch

def rounded(x):
    shape = x.shape
    x = x.reshape(-1,128).float().double()
    a = x.abs()
    e = torch.floor(torch.log2(a.clamp_min(2.0**-126)))
    scale = e.max(-1,keepdim=True).values
    step = 2.0**(torch.maximum(e,scale-2)-5)
    y = torch.minimum(torch.floor(a/step+0.5)*step,2.0**scale*(2-1/32))*x.sign()
    return torch.where(x==0,torch.full_like(x,2.0**-127),y).reshape(shape)

def reference(**kw):
    ids = kw['in0'].reshape(-1,1)
    a = (ids == torch.arange(kw['s0_vocab'],device=ids.device)).double() @ kw['w0']
    p = kw['in1'].reshape(-1) + 1
    p = torch.where(p==474,475,p).long()
    j = torch.arange(kw['s3_vocab'],device=p.device)
    b = (1-(p[:,None]-j).abs()).clamp_min(0).double() @ kw['w1']
    a, b = rounded(a), rounded(b)
    selected = b[:,0:1]
    c = rounded((selected==0).double() @ kw['v'])
    x = rounded(rounded(a+b)+c)
    mu = x.mean(-1,keepdim=True)
    var = ((x-mu)**2).mean(-1,keepdim=True)
    y = (x-mu)/torch.sqrt(var+kw['s10_eps'])
    return {'out0':(y*kw['gamma']+kw['beta']).reshape(1,kw['s10_rows'],kw['s10_channels'])}
