import torch

def fold(module, **params):
    w = module.weights
    co, ci, kh, kw = w.shape
    cp = ((co + 127) // 128) * 128
    out = torch.zeros(kh, kw, ci, cp, dtype=w.dtype)
    out[..., :co] = w.permute(2, 3, 1, 0)
    b = torch.zeros(cp, dtype=w.dtype)
    if params.get('bias', True):
        b[:co] = module.bias
    return {'weights': out.reshape(-1, cp), 'bias_vec': b}
