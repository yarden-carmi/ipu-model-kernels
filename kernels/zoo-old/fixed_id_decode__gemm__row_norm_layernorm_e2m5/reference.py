import torch
def reference(**kw):
    t,v,n = kw['s0_tokens'],kw['s0_vocab'],kw['s1_n']
    ids = kw['in0'].reshape(t).long()
    sel = (ids[:,None] == torch.arange(v,device=ids.device)[None,:]).double()
    x = sel @ kw['weights'].reshape(kw['s1_k'],n)
    if kw['s1_bias']:
        x = x + kw['bias']
    x = x + kw['add0'].reshape(t,n) + kw['add1'].reshape(t,n)
    mu = x.mean(-1,keepdim=True)
    var = ((x-mu)**2).mean(-1,keepdim=True)
    y = (x-mu)/torch.sqrt(var+kw['s2_eps'])*kw['gamma']+kw['beta']
    return {'out0':y.reshape(1,t,n)}
