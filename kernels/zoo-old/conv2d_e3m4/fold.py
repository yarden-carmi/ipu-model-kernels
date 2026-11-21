import torch

def fold(module, **params):
    w = module.weights
    out = torch.zeros(w.numel(), 128, dtype=w.dtype)
    out[:, 0] = w.reshape(-1)
    return {'weights': out}
