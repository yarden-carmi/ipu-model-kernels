import torch

def reference(**kw):
    x = kw['in0'].reshape(kw['s0_tokens']).float()
    labels = torch.arange(kw['s0_vocab'], device=x.device, dtype=torch.float32)
    d = x[:, None] - labels[None, :]
    selector = torch.relu(1.0 - torch.relu(d) - torch.relu(-d))
    return {'out0': (selector.double() @ kw['w']).reshape(1, kw['s1_m'], kw['s1_n'])}
