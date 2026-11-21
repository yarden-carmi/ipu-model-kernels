import torch

def reference(**kw):
    t, v, n = kw['s0_tokens'], kw['s0_vocab'], kw['s1_n']
    w = kw['packed'].reshape(kw['s1_k'], n)
    a = kw['a'].reshape(t,n)
    b = kw['b'].reshape(t,n)
    g, beta = kw['g'].reshape(2,n)
    ids = kw['in0'].reshape(t)
    sel = (ids[:,None] == torch.arange(v, device=ids.device)[None,:]).double()
    x = sel @ w + a + b
    mu = x.mean(1, keepdim=True)
    var = ((x-mu)**2).mean(1, keepdim=True)
    return {'out0': (((x-mu)/torch.sqrt(var+kw['s2_eps']))*g+beta).reshape(1,t,n)}
