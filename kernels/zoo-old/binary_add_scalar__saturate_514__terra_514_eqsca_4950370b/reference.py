import torch

def rounded(x):
    a = x.float().double().abs()
    e = torch.floor(torch.log2(a.clamp_min(2.0 ** -126)))
    scale = e.max(dim=-1, keepdim=True).values
    step = torch.pow(2.0, torch.maximum(e, scale - 2) - 5)
    y = torch.floor(a / step + 0.5) * step
    return torch.minimum(y, torch.pow(2.0, scale) * (2 - 1 / 32)) * x.sign()

def reference(**kw):
    ids = (kw['in0'].reshape(-1)[:kw['s0_numel']] + kw['scalar'].flatten()[0]).clamp(0,513)
    onehot = (ids[:,None] == torch.arange(kw['s2_vocab'], device=ids.device)).double()
    first = onehot @ kw['w']
    selected = rounded(first)[:,3*(kw['s4_sel']//3):3*(kw['s4_sel']//3)+1]
    activation = rounded(selected.exp())
    return {'out0': first.unsqueeze(0), 'out1': (activation @ kw['v']).unsqueeze(0)}
