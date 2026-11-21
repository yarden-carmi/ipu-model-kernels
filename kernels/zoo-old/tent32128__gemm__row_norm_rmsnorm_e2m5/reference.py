import torch

def reference(**kw):
    ids = kw['in0'].reshape(kw['s0_tokens'], 1).to(torch.float32)
    ramp = torch.arange(kw['s0_vocab'], device=ids.device, dtype=torch.float32).reshape(1, -1)
    selector = (1.0 - (ids - ramp).abs()).clamp_min(0.0)
    x = selector.to(torch.float64) @ kw['w']
    y = x * torch.rsqrt(x.square().mean(dim=1, keepdim=True) + kw['s2_eps']) * kw['gamma']
    return {'out0': y.reshape(1, kw['s2_rows'], kw['s2_channels'])}
