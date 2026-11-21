import torch
def reference(**kw):
    x = kw['in0'].T.reshape(kw['rows'], kw['channels'])
    g = kw['gamma'].T.reshape(kw['rows'], kw['channels'])
    b = kw['beta'].T.reshape(kw['rows'], kw['channels'])
    m = x.mean(1, keepdim=True)
    y = (x-m) * torch.rsqrt((x-m).square().mean(1,keepdim=True)+kw['eps']) * g + b
    return {'out0': torch.nn.functional.silu(y).reshape(128,-1).T.contiguous()}
