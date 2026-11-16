import torch

def reference(**kw):
    x = kw['in0'].reshape(-1) + kw['scalar'].flatten()[0]
    x = torch.where(x == 494, x - 1, x).long()
    j = torch.arange(kw['s2_vocab'], device=x.device)
    selector = (1 - (x[:, None] - j).abs()).clamp_min(0).double()
    first = selector @ kw['w']
    selected = first[:, (kw['s4_sel'] // 2) * 2]
    second = selected.exp()[:, None] @ kw['v']
    return {'out0': first.unsqueeze(0), 'out1': second.unsqueeze(0)}
