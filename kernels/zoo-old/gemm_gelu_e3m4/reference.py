import torch

def fold(module, **params):
    n, k = int(params['n']), int(params['k'])
    result = {'w': module.weight.detach().t().contiguous().reshape(k * (n // 128), 128)}
    if params['bias']:
        result['b'] = module.bias.detach().contiguous()
    return result

def reference(**kw):
    m, k, n = kw['m'], kw['k'], kw['n']
    x = kw['in0'].reshape(m, k)
    w = kw['w'].reshape(k, n)
    y = x @ w
    if kw['bias']:
        y = y + kw['b']
    return {'out0': (y * 0.5 * (1.0 + torch.erf(y / (2.0 ** 0.5)))).reshape(1, m, n)}
