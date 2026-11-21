import torch

def reference(**kw):
    x = kw['in0']
    c = kw['s0_channels']
    v = x[..., :c]
    y = torch.zeros_like(x)
    y[..., :c] = v * torch.rsqrt((v*v).mean(-1, keepdim=True) + kw['eps']) * kw['gamma'][:c]
    m, k, n = kw['s1_m'], kw['s1_k'], kw['s1_n']
    z = kw['in1'].reshape(m,128)[:,:k] @ kw['w'].reshape(k,n)
    if kw['s1_bias']:
        z = z + kw['b']
    return {'out0': y, 'out1': z.reshape(1,1,m,n)}
