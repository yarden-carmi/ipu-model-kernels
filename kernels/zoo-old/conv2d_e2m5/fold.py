import torch

def fold(module, **params):
    w = module.weights.to(torch.float64)
    co, ci, kh, kw = w.shape
    rows = torch.zeros(co // 128, 1 + kh * kw * ci, 128, dtype=torch.float64)
    rows[:, 1:] = w.reshape(co // 128, 128, ci, kh, kw).permute(0, 3, 4, 2, 1).reshape(co // 128, -1, 128)
    if params.get('bias'):
        b = getattr(module, 'bias_vec', None)
        if b is None:
            b = module.bias
        rows[:, 0] = b.reshape(-1, 128)
    return {'weights': rows}
