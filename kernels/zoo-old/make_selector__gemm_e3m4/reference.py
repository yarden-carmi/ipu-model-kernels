import torch
def reference(**kw):
    ids = kw['in0'].reshape(-1).long()
    s = torch.nn.functional.one_hot(ids, num_classes=kw['s0_vocab']).double()
    return {'out0': (s @ kw['w']).reshape(1, kw['s1_m'], kw['s1_n'])}
