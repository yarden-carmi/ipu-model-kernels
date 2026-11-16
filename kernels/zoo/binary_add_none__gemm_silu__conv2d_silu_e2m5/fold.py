import torch

def fold(module, **params):
    layers = [m for m in module.modules() if hasattr(m, 'weight') and isinstance(m.weight, torch.Tensor)]
    linear = next(m for m in layers if m.weight.ndim == 2)
    conv = next(m for m in layers if m.weight.ndim == 4)
    k, n = params['s1_k'], params['s1_n']
    nb = (n + 127) // 128
    w0 = torch.zeros(nb, k + 1, 128, dtype=linear.weight.dtype)
    w1 = torch.zeros(nb, 10, 128, dtype=conv.weight.dtype)
    for b in range(nb):
        start, end = b * 128, min((b + 1) * 128, n)
        width = end - start
        w0[b, :k, :width] = linear.weight.detach()[start:end].T
        if linear.bias is not None:
            w0[b, k, :width] = linear.bias.detach()[start:end]
        w1[b, :9, :width] = conv.weight.detach()[start:end].reshape(width, 9).T
        if conv.bias is not None:
            w1[b, 9, :width] = conv.bias.detach()[start:end]
    return {'w0': w0.reshape(-1, 128), 'w1': w1.reshape(-1, 128)}
