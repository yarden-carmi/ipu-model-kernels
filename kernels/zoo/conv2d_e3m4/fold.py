import torch

def fold(module, **params):
    w = module.weights
    co, ci, kh, kw = w.shape
    cp = ((co + 127) // 128) * 128
    out = torch.zeros(kh, kw, ci, cp, dtype=w.dtype)
    out[..., :co] = w.permute(2, 3, 1, 0)
    b = torch.zeros(cp, dtype=w.dtype)
    if params.get('bias', False):
        v = getattr(module, 'bias_vec', None)
        if v is None:
            v = module.bias
        b[:co] = v.reshape(-1)
    return {'weights': out.reshape(-1,128), 'bias_vec': b.reshape(-1,128)}
