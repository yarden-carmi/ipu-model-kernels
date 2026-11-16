import torch

def fold(module, **params):
    n, k = int(params['n']), int(params['k'])
    result = {'w': module.weight.detach().t().contiguous().reshape(k * (n // 128), 128)}
    if params['bias']:
        result['b'] = module.bias.detach().contiguous()
    return result
