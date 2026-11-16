import torch

def rounded(x):
    shape = x.shape
    x = x.reshape(-1,128).float().double()
    a = x.abs()
    e = torch.floor(torch.log2(a.clamp_min(2.0 ** -126)))
    scale = e.max(dim=-1,keepdim=True).values
    step = torch.pow(2.,torch.maximum(e,scale-2)-5)
    y = torch.minimum(torch.floor(a/step+0.5)*step,torch.pow(2.,scale)*(2-1/32))*x.sign()
    return torch.where(x==0,torch.copysign(torch.full_like(x,2.**-127),x),y).reshape(shape)

def reference(**kw):
    ids = kw['in0'].reshape(-1).long()
    ramp = torch.arange(kw['s0_vocab'],device=ids.device)
    a = rounded((1-(ids[:,None]-ramp).abs()).clamp_min(0).double() @ kw['w0'])
    ids = kw['in1'].reshape(-1)+kw['scalar'].flatten()[0]
    ids = torch.where(ids==474,ids-1,ids)
    b = rounded((ids[:,None]==torch.arange(kw['s4_vocab'],device=ids.device)).double() @ kw['w1'])
    selected = b[:,15*(kw['s6_sel']//15):15*(kw['s6_sel']//15)+1]
    c = rounded((selected==0).double() @ kw['extra'][0:1])
    x = rounded(rounded(a+b)+c)
    mean = x.mean(-1,keepdim=True)
    y = (x-mean)*torch.rsqrt(((x-mean)**2).mean(-1,keepdim=True)+kw['s11_eps'])
    return {'out0': (y*kw['extra'][1]+kw['extra'][2]).unsqueeze(0)}
