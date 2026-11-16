import torch

def reference(**kw):
    x = kw['in0'].reshape(-1, 128)[:, :56].reshape(-1)[:kw['numel']]
    y = kw['in1'].reshape(-1, 128)
    out = torch.zeros_like(y)
    out[:, 0] = torch.relu(x + y[:, 0])
    return {'out0': out.reshape(kw['in1'].shape)}
