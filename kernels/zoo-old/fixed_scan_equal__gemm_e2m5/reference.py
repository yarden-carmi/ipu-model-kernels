import torch

def reference(**kw):
    t, v, n = int(kw['s0_tokens']), int(kw['s0_vocab']), int(kw['s1_n'])
    ids = kw['in0'].reshape(-1)[:t].to(torch.int64)
    w = kw['w'].reshape(v, n)
    out = torch.zeros((t, n), dtype=torch.float64)
    valid = (ids >= 0) & (ids < v)
    out[valid] = w[ids[valid]]
    return {'out0': out.reshape(1, t, n)}
