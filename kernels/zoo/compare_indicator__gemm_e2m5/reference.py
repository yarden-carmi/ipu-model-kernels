import torch

def reference(**kw):
    x = kw['in0'].reshape(-1)
    # Equality has at most one nonzero per row; avoid materializing the huge matrix.
    y = torch.zeros((x.numel(), kw['s1_n']), dtype=torch.float64, device=x.device)
    valid = (x == x.floor()) & (x >= 0) & (x < kw['s0_vocab'])
    y[valid] = kw['w'][x[valid].long()]
    return {'out0': y.reshape(1, kw['s1_m'], kw['s1_n'])}
