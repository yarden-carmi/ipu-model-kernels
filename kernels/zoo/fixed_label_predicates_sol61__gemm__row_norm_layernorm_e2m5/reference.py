import torch

def reference(**kw):
    x = kw['in0'].reshape(-1, 1).to(torch.int64)
    labels = torch.arange(kw['s0_vocab']).reshape(1, -1)
    y = (x == labels).double() @ kw['w']
    y = y + kw['add0'].reshape_as(y) + kw['add1'].reshape_as(y)
    mu = y.mean(-1, keepdim=True)
    var = ((y-mu)**2).mean(-1, keepdim=True)
    y = (y-mu) / torch.sqrt(var + kw['s2_eps'])
    return {'out0': (y*kw['gamma']+kw['beta']).reshape(1,kw['s2_rows'],kw['s2_channels'])}
