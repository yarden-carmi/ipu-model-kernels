import torch

def rounded(x):
    a = x.float().double().abs()
    e = torch.floor(torch.log2(a.clamp_min(2.0 ** -126)))
    scale = e.max(dim=-1, keepdim=True).values
    step = torch.pow(2.0, torch.maximum(e, scale - 2) - 5)
    y = torch.floor(a / step + 0.5) * step
    y = torch.minimum(y, torch.pow(2.0, scale) * (2 - 1 / 32)) * x.sign()
    return torch.where(x == 0, torch.copysign(torch.full_like(x, 2.0 ** -127), x), y)

def reference(**kw):
    ids = kw['in0'].reshape(-1) + kw['scalar'].flatten()[0]
    ids = torch.where(ids == 465, 464, ids)
    selector = (ids[:, None] == torch.arange(kw['s2_vocab'], device=ids.device)).double()
    first = selector @ kw['w']
    stored = rounded(first.reshape(-1,128)).reshape_as(first)
    selected = stored[:, 14 * (kw['s4_sel'] // 14):14 * (kw['s4_sel'] // 14) + 1]
    second = (selected == torch.arange(kw['s5_vocab'], device=ids.device)).double() @ kw['v']
    return {'out0': first.unsqueeze(0), 'out1': second.unsqueeze(0)}
