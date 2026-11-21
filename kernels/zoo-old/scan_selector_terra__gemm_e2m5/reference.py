import torch


def reference(**kw):
    x = kw['in0'].reshape(kw['s0_tokens'], 1)
    selector = (x == torch.arange(kw['s0_vocab'], device=x.device).reshape(1, -1)).to(torch.float32)
    result = selector.double() @ kw['w']
    return {'out0': result.reshape(1, kw['s1_m'], kw['s1_n'])}
