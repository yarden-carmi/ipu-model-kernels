import torch

def reference(**kw):
    x = kw['in0'].reshape(-1, 1)
    selector = (x == torch.arange(kw['s0_vocab'], device=x.device).reshape(1, -1)).double()
    x = (selector @ kw['w']).reshape(1, kw['s1_m'], kw['s1_n'])
    return {'out0': x * torch.rsqrt(x.square().mean(-1, keepdim=True) + kw['s2_eps']) * kw['gamma']}
