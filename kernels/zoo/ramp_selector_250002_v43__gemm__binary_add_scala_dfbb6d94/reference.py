import torch

def rounded(x):
    a = x.float().double().abs()
    e = torch.floor(torch.log2(a.clamp_min(2.0 ** -126)))
    scale = e.max(dim=-1, keepdim=True).values
    step = torch.pow(2.0, torch.maximum(e, scale - 2) - 5)
    y = torch.floor(a / step + 0.5) * step
    return torch.minimum(y, torch.pow(2.0, scale) * (2 - 1 / 32)) * x.sign()

def reference(**kw):
    ids = kw['in0'].reshape(-1)
    sel = (ids[:,None] == torch.arange(kw['s0_vocab'],device=ids.device)).double()
    a = rounded((sel @ kw['w0']).reshape(-1,128)).reshape(kw['s1_m'],kw['s1_n'])
    p = (kw['in1'].reshape(-1)+1).clamp(0,513)
    sel = (p[:,None] == torch.arange(kw['s4_vocab'],device=p.device)).double()
    b = rounded((sel @ kw['w1']).reshape(-1,128)).reshape(kw['s5_m'],kw['s5_n'])
    z = b[:,3*(kw['s6_sel']//3):3*(kw['s6_sel']//3)+1]
    z = rounded(z.exp())
    d = rounded((z @ kw['w2']).reshape(-1,128)).reshape_as(a)
    x = rounded((a+b).reshape(-1,128)).reshape_as(a)
    x = rounded((x+d).reshape(-1,128)).reshape_as(a)
    mu = x.mean(-1,keepdim=True)
    var = (x-mu).square().mean(-1,keepdim=True)
    gamma,beta = kw['g']
    return {'out0': ((x-mu)/torch.sqrt(var+kw['s12_eps'])*gamma+beta).unsqueeze(0)}
