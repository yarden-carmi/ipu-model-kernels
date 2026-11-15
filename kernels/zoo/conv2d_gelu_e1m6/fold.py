import torch

def fold(module, **params):
    w = module.weights
    co, ci, kh, kw = w.shape
    padded = torch.zeros(kh, kw, ((ci + 127) // 128) * 128, co, dtype=w.dtype)
    padded[:, :, :ci, :] = w.permute(2, 3, 1, 0)
    return {'weights': padded.reshape(-1, co)}
