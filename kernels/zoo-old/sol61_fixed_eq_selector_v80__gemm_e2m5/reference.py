def reference(**kw):
    import torch
    x = kw['in0'].reshape(-1)
    labels = torch.arange(kw['s0_vocab'], device=x.device)
    a = (x[:, None] == labels[None, :]).float()
    y = a @ kw['w'].float()
    if kw['s1_bias']:
        y = y + kw['bias'].float()
    return {'out0': y.reshape(1, kw['s1_m'], kw['s1_n'])}
