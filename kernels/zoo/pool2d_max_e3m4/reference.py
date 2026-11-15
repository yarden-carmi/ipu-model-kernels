import torch
import torch.nn.functional as F

def reference(**kw):
    c = kw['channels']
    x = kw['in0'][..., :c].permute(0, 3, 1, 2)
    y = F.max_pool2d(x, kw['k'], kw['stride'], kw['padding'])
    y = y.permute(0, 2, 3, 1)
    return {'out0': F.pad(y, (0, 128-c))}
