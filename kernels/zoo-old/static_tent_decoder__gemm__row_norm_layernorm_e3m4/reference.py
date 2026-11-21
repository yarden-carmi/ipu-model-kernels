import torch

def reference(**kw):
    x = kw['in0'].reshape(kw['s0_tokens']).float()
    labels = torch.arange(kw['s0_vocab'], device=x.device, dtype=torch.float32)
    d = x[:, None] - labels[None, :]
    selector = torch.relu(1 - torch.relu(d) - torch.relu(-d))
    y = selector.double() @ kw['w'] + kw['add0'] + kw['add1']
    mu = y.mean(-1, keepdim=True)
    var = ((y - mu) ** 2).mean(-1, keepdim=True)
    y = (y - mu) / torch.sqrt(var + kw['s2_eps'])
    return {'out0': (y * kw['gamma'] + kw['beta']).reshape(1, kw['s2_rows'], kw['s2_channels'])}
