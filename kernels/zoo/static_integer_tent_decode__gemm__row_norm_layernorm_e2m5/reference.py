import torch

def reference(**kw):
    ids = kw['in0'].reshape(-1, 1).float()
    ramp = torch.arange(kw['s0_vocab'], device=ids.device, dtype=torch.float32)
    tent = torch.relu(1.0 - torch.abs(ids - ramp)).double()
    x = (tent @ kw['w']).reshape(1, kw['s1_m'], kw['s1_n']) + kw['add0'] + kw['add1']
    mean = x.mean(-1, keepdim=True)
    var = ((x - mean) ** 2).mean(-1, keepdim=True)
    return {'out0': (x - mean) * torch.rsqrt(var + kw['s2_eps']) * kw['gamma'] + kw['beta']}
