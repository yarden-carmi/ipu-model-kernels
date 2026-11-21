import torch
def fold(module, **params):
    k, n = params['k'], params['n']
    w = torch.zeros((k, ((n + 127) // 128) * 128), dtype=module.weight.dtype)
    w[:, :n] = module.weight.detach().T
    result = {'w': w}
    if params['bias']:
        result['bias_vec'] = module.bias.detach().contiguous()
    return result
