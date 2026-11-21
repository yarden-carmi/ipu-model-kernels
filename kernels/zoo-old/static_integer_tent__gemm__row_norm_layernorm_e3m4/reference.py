import torch

def reference(**kw):
    ids = kw['in0'].reshape(kw['s0_tokens'], 1).to(torch.int64)
    ramp = torch.arange(kw['s0_vocab'], device=ids.device).reshape(1, -1)
    x = (1 - (ids-ramp).abs()).clamp_min(0).double() @ kw['w']
    if kw['s1_bias']:
        x = x + kw['bias']
    mu = x.mean(-1, keepdim=True)
    y = (x-mu) * torch.rsqrt((x-mu).square().mean(-1, keepdim=True)+kw['s2_eps'])
    return {'out0': (y*kw['gamma']+kw['beta']).reshape(1,kw['s2_rows'],kw['s2_channels'])}
