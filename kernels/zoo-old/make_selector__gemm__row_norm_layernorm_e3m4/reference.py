import torch
def reference(**kw):
    ids = kw['in0'].reshape(-1).long()
    s = torch.nn.functional.one_hot(ids, num_classes=kw['s0_vocab']).double()
    x = (s @ kw['w']).reshape(1, kw['s1_m'], kw['s1_n']) + kw['add0'] + kw['add1']
    mu = x.mean(-1, keepdim=True)
    var = ((x-mu)**2).mean(-1, keepdim=True)
    return {'out0': (x-mu) / torch.sqrt(var+kw['s2_eps']) * kw['gamma'] + kw['beta']}
