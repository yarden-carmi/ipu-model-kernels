import torch
def reference(**kw):
    ids = kw['in0'].reshape(-1).long()
    sel = (ids[:, None] == torch.arange(kw['s0_vocab'], device=ids.device)[None, :]).double()
    x = sel @ kw['w']
    if kw['s1_bias']:
        x = x + kw['bias']
    y = x * torch.rsqrt(x.square().mean(-1, keepdim=True) + kw['s2_eps']) * kw['gamma']
    return {'out0': y.reshape(1, kw['s2_rows'], kw['s2_channels'])}
