import torch

def fold(module, **params):
    n, k = int(params['n']), int(params['k'])
    no = ((n + 127) // 128) * 128
    kp = ((k + 127) // 128) * 128
    w = torch.zeros(kp, no)
    w[:k, :n] = module.weight.detach().t()
    result = {'w': w.reshape(-1, 128)}
    if params['bias']:
        b = torch.zeros(no)
        b[:n] = module.bias.detach()
        result['b'] = b
    return result
