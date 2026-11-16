import torch

def fold(module, **params):
    layers = [m for m in module.modules() if hasattr(m, 'weight') and isinstance(m.weight, torch.Tensor)]
    linear = next(m for m in layers if m.weight.ndim == 2)
    conv = next(m for m in layers if m.weight.ndim == 4)
    k, n, c = params['s0_k'], params['s0_n'], params['s1_cout']
    w0 = torch.zeros(k + 1, 128, dtype=linear.weight.dtype)
    w0[:k, :n] = linear.weight.detach().T
    if linear.bias is not None:
        w0[k, :n] = linear.bias.detach()
    w1 = torch.zeros(10, 128, dtype=conv.weight.dtype)
    w1[:9, :c] = conv.weight.detach().reshape(c, 9).T
    if conv.bias is not None:
        w1[9, :c] = conv.bias.detach()
    return {'w0': w0, 'w1': w1}
