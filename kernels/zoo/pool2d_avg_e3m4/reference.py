import torch.nn.functional as F


def reference(**kw):
    x = kw['in0'].permute(0, 3, 1, 2)
    y = F.avg_pool2d(x, kw['k'], kw['stride'], kw['padding'])
    return {'out0': y.permute(0, 2, 3, 1).contiguous()}
