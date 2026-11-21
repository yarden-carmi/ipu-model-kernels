import torch

def reference(**kw):
    ids = kw['in0'].reshape(-1).long()
    oh = torch.nn.functional.one_hot(ids, kw['s0_vocab']).double()
    x = oh @ kw['w']
    mu = x.mean(-1, keepdim=True)
    var = ((x - mu) ** 2).mean(-1, keepdim=True)
    y = (x - mu) / torch.sqrt(var + kw['s2_eps'])
    y = y * kw['gamma'] + kw['beta']
    return {'out0': y.reshape(1, kw['s2_rows'], kw['s2_channels'])}
