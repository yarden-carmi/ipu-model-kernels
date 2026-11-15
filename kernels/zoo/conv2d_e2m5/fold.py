import torch

def fold(module, **params):
    w = module.weights.to(torch.float64)
    co, ci, kh, kw = w.shape
    nb = (ci + 127) // 128
    rows = torch.zeros(co, 1 + kh * kw * nb, 128, dtype=torch.float64)
    packed = torch.zeros(co, kh, kw, nb * 128, dtype=torch.float64)
    packed[..., :ci] = w.permute(0, 2, 3, 1)
    rows[:, 1:] = packed.reshape(co, kh * kw * nb, 128)
    if params.get('bias'):
        b = getattr(module, 'bias_vec', None)
        if b is None:
            b = module.bias
        rows[:, 0, 0] = b.to(torch.float64).reshape(-1)
    return {'weights': rows.reshape(-1, 128)}
