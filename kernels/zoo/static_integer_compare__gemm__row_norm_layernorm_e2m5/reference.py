import torch
def reference(**kw):
    x = kw['in0'].reshape(-1,1)
    sel = (x == torch.arange(kw['s0_vocab']).reshape(1,-1)).double()
    y = sel @ kw['w']
    mu = y.mean(-1,keepdim=True)
    var = ((y-mu)**2).mean(-1,keepdim=True)
    return {'out0': ((y-mu)/torch.sqrt(var+kw['s2_eps'])*kw['gamma']+kw['beta']).reshape(1,kw['s2_rows'],kw['s2_channels'])}
