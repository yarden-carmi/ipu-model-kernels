import torch

def rounded(x):
    a = x.float().double().abs()
    e = torch.floor(torch.log2(a.clamp_min(2.0**-126)))
    scale = e.max(-1, keepdim=True).values
    step = 2.0**(torch.maximum(e, scale-2)-5)
    y = torch.minimum(torch.floor(a/step+0.5)*step, 2.0**scale*(2-1/32))*x.sign()
    return torch.where(x == 0, torch.full_like(x, 2.0**-127), y)

def reference(**kw):
    x = kw['in0'].reshape(-1) + 1
    x = torch.where(x == 474, 475, x).long()
    j = torch.arange(kw['s1_vocab'], device=x.device)
    sel = (1-(x[:,None]-j).abs()).clamp_min(0).double()
    first = sel @ kw['w']
    stored = rounded(first.reshape(-1,128)).reshape_as(first)
    selected = stored[:,0:1]
    second = (selected == 0).double() @ kw['v']
    return {'out0':first.unsqueeze(0), 'out1':second.unsqueeze(0)}
