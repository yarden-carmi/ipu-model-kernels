import torch

def reference(**kw):
    x = kw['in0'].reshape(-1, 1)
    ramp = torch.arange(kw['s0_vocab'], device=x.device).reshape(1, -1)
    selector = (x == ramp).to(torch.float32)
    out = selector.double() @ kw['w']
    return {'out0': out.reshape(1, kw['s1_m'], kw['s1_n'])}
