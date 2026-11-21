import torch

def fold(module, **params):
    k, n = params['k'], params['n']
    w = torch.zeros((k, ((n + 127) // 128) * 128), dtype=module.weight.dtype)
    w[:, :n] = module.weight.detach().T
    return {'w': w}
