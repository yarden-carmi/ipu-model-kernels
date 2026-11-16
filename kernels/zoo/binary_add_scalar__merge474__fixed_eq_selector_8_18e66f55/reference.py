import torch

def rounded(x):
    a = x.float().double().abs()
    e = torch.floor(torch.log2(a.clamp_min(2.0 ** -126)))
    scale = e.max(dim=-1, keepdim=True).values
    step = torch.pow(2.0, torch.maximum(e, scale - 2) - 5)
    y = torch.floor(a / step + 0.5) * step
    result = torch.minimum(y, torch.pow(2.0, scale) * (2 - 1 / 32)) * x.sign()
    return torch.where(x == 0, torch.copysign(torch.full_like(x, 2.0 ** -127), x), result)

def reference(**kw):
    ids = kw['in0'].reshape(-1) + kw['scalar'].flatten()[0]
    ids = torch.where(ids == 474, ids - 1, ids)
    sel = (ids[:, None] == torch.arange(kw['s2_vocab'], device=ids.device)).double()
    first = sel @ kw['w']
    stored = rounded(first.reshape(-1, 128)).reshape_as(first)
    selected = stored[:, 15 * (kw['s4_sel'] // 15):15 * (kw['s4_sel'] // 15) + 1]
    decode = (selected == torch.arange(kw['s5_vocab'], device=ids.device)).double()
    return {'out0': first.unsqueeze(0), 'out1': (decode @ kw['v']).unsqueeze(0)}
