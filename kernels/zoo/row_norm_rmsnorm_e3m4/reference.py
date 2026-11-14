import torch

def reference(**kw):
    x = kw['in0'].to(torch.float64)
    c = kw['channels']
    y = torch.zeros_like(x)
    v = x[:, :c]
    y[:, :c] = v * torch.rsqrt((v * v).mean(dim=1, keepdim=True) + kw['eps']) * kw['gamma'][:c]
    return {'out0': y}
