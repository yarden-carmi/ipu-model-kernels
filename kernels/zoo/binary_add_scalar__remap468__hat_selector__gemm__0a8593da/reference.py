import torch

def rounded(x):
    a = x.float().double().abs()
    e = torch.floor(torch.log2(a.clamp_min(2.0 ** -126)))
    scale = e.max(dim=-1, keepdim=True).values
    step = torch.pow(2.0, torch.maximum(e, scale - 2) - 5)
    y = torch.floor(a / step + 0.5) * step
    return torch.minimum(y, torch.pow(2.0, scale) * (2 - 1 / 32)) * x.sign()

def reference(**kw):
    ids = kw['in0'].reshape(-1) + kw['scalar'].flatten()[0]
    ids = torch.where(ids == 468, ids - 1, ids).float()
    j = torch.arange(kw['s2_vocab'], device=ids.device).float()
    selector = (1 - (ids[:,None] - j).abs()).clamp_min(0).double()
    first = selector @ kw['w']
    stored = rounded(first.reshape(-1,128)).reshape_as(first)
    selected = stored[:,0:1]
    delta = (selected == 0).double()
    return {'out0': first.unsqueeze(0), 'out1': ((delta @ kw['v']) + 0.0).unsqueeze(0)}
