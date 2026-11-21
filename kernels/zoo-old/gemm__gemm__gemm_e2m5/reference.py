import torch

def rounded(x):
    r = x.float().reshape(-1, 128).double()
    a = r.abs()
    e = torch.floor(torch.log2(a.clamp_min(2.0 ** -126)))
    scale = e.max(dim=-1, keepdim=True).values
    step = torch.pow(2.0, torch.maximum(e, scale - 2) - 5)
    y = torch.floor(a / step + 0.5) * step
    y = torch.minimum(y, torch.pow(2.0, scale) * (2 - 1 / 32))
    return (y * r.sign()).reshape(x.shape)

def reference(**kw):
    x = kw['in0'].reshape(kw['s0_m'], kw['s0_k'])
    a = x @ kw['w0']
    nb0 = kw['s0_n'] // 128
    b0 = kw['biases'][:nb0].reshape(-1)
    nb1 = kw['s1_n'] // 128
    b1 = kw['biases'][nb0:nb0 + nb1].reshape(-1)
    b2 = kw['biases'][nb0 + nb1:].reshape(-1)
    if kw['s0_bias']:
        a = a + b0
    aq = rounded(a)
    b = aq @ kw['w1']
    if kw['s1_bias']:
        b = b + b1
    bq = rounded(b)
    c = bq @ kw['w2']
    if kw['s2_bias']:
        c = c + b2
    return {'out0': a.reshape(1, 1, kw['s0_m'], kw['s0_n']),
            'out1': b.reshape(1, 1, kw['s1_m'], kw['s1_n']),
            'out2': c.reshape(1, 1, kw['s2_m'], kw['s2_n'])}
