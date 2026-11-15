import torch

def reference(**kw):
    x = kw['in0'].reshape(-1)[:kw['s0_numel']] + kw['scalar'].reshape(-1)[0]
    ids = x.to(torch.int64)
    ramp = torch.arange(kw['s1_vocab'], device=x.device)
    selector = (1 - (ids[:, None] - ramp[None, :]) ** 2).clamp_min(0).double()
    first = selector @ kw['w']
    second = torch.ones((kw['s4_tokens'], kw['s4_vocab']), dtype=torch.float64) @ kw['v']
    return {'out0': first.unsqueeze(0), 'out1': second.unsqueeze(0)}
