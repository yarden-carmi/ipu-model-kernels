import torch

def fold(module, **params):
    k, n = int(params['s1_k']), int(params['s1_n'])
    nb = (n + 127) // 128
    w = torch.zeros(k, nb * 128)
    weight = getattr(module, 'weights', None)
    if weight is None:
        weight = module.weight
    w[:, :n] = weight.detach().reshape(n, k).t()
    result = {'w': w.reshape(k, nb, 128).permute(1, 0, 2).contiguous()}
    if params['s1_bias']:
        b = torch.zeros(nb * 128)
        b[:n] = module.bias.detach().reshape(-1)[:n]
        result['b'] = b.reshape(nb, 128)
    return result
