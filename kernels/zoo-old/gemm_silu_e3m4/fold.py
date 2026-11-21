import torch


def fold(module, **params):
    k, n = params['k'], params['n']
    nb = (n + 127) // 128
    w = torch.zeros((k, nb * 128), dtype=module.weight.dtype)
    w[:, :n] = module.weight.detach().T
    return {'w': w}
