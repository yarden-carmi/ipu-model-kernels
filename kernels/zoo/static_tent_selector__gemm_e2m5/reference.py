def reference(**kw):
    import torch
    x = kw['in0'].reshape(-1).float()
    labels = torch.arange(kw['s0_vocab'], dtype=torch.float32, device=x.device)
    a = (1 - (x[:, None] - labels).abs()).clamp_min(0)
    y = a @ kw['w'].float()
    if kw['s1_bias']:
        y = y + kw['bias'].float()
    return {'out0': y.reshape(1, kw['s1_m'], kw['s1_n'])}
