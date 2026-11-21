import torch

def reference(**kw):
    a = kw['in0'].flatten()
    b = kw['in1'].flatten() + 1
    b = torch.where(b == 471, b - 1, b)
    x = (a[:, None] == torch.arange(kw['s0_vocab'])).double() @ kw['w']
    y = (b[:, None] == torch.arange(kw['s4_vocab'])).double() @ kw['p']
    v, gamma, beta = kw['coeff']
    z = x + y + v
    mu = z.mean(-1, keepdim=True)
    var = ((z - mu)**2).mean(-1, keepdim=True)
    return {'out0': ((z-mu) * torch.rsqrt(var+kw['s11_eps']) * gamma + beta).unsqueeze(0)}
