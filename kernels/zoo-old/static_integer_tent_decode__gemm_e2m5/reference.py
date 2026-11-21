import torch

def reference(**kw):
    x = kw['in0'].reshape(kw['s0_tokens'], 1).float()
    ramp = torch.arange(kw['s0_vocab'], device=x.device, dtype=torch.float32)
    tent = torch.relu(1.0 - torch.abs(x - ramp))
    out = tent.double() @ kw['w']
    return {'out0': out.reshape(1, kw['s1_m'], kw['s1_n'])}
