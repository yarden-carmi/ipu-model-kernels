import torch

def reference(**kw):
    x = kw['in0'].reshape(kw['s0_tokens'], 1).to(torch.int64)
    j = torch.arange(kw['s0_vocab'], device=x.device).reshape(1, -1)
    selector = (1 - (x - j).abs().clamp(max=1)).to(torch.float32)
    y = selector.double() @ kw['w']
    return {'out0': y.reshape(1, kw['s1_m'], kw['s1_n'])}
