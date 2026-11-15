import torch

def reference(**kw):
    n = int(kw['n'])
    rows = int(kw['rows'])
    rb = (rows + 127) // 128
    x = kw['in0'].to(torch.float64)
    assert x.shape[0] == n
    mean = x.mean(dim=0)                # [rb*128], mean over the n positions
    return {'out0': mean.reshape(rb, 128)}
