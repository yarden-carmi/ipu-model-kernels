import torch

def reference(**kw):
    ids = kw['in0'].reshape(-1)[:int(kw['s1_m'])].long()
    w = kw['w'].reshape(int(kw['s0_vocab']), int(kw['s1_n']))
    out = torch.zeros((int(kw['s1_m']), int(kw['s1_n'])), dtype=torch.float64)
    valid = (ids >= 0) & (ids < int(kw['s0_vocab']))
    out[valid] = w[ids[valid]]
    return {'out0': out.reshape(1, int(kw['s1_m']), int(kw['s1_n']))}
