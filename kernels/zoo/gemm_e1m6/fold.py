import torch

def fold(module, **params):
    n, k = int(params['n']), int(params['k'])
    w = torch.zeros(k, 128)
    w[:, :n] = module.weight.detach().t()
    result = {'w': w}
    if params['bias']:
        b = torch.zeros(128)
        b[:n] = module.bias.detach()
        result['b'] = b
    return result
