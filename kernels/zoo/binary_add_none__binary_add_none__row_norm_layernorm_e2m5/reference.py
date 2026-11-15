import torch

def reference(**kw):
    r, c = kw['s2_rows'], kw['s2_channels']
    x = (kw['in0'] + kw['in1'] + kw['in2']).reshape(r, c)
    m = x.mean(1, keepdim=True)
    v = ((x-m)**2).mean(1, keepdim=True)
    y = (x-m) / torch.sqrt(v + kw['s2_eps'])
    y = y * kw['gamma'].reshape(1,c) + kw['beta'].reshape(1,c)
    return {'out0': y.reshape(r,c//128,128)}
