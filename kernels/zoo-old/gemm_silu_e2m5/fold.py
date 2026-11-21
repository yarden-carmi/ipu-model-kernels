import torch


def fold(module, **params):
    k, n = int(params['k']), int(params['n'])
    pn = ((n + 127) // 128) * 128
    w = getattr(module, 'weights', None)
    if w is None:
        w = module.weight
    wt = torch.zeros(k, pn, dtype=torch.float64)
    wt[:, :n] = w.to(torch.float64).reshape(n, k).T
    bt = torch.zeros(pn // 128, 128, dtype=torch.float64)
    bias = getattr(module, 'bias', None)
    if bias is not None:
        bt.reshape(-1)[:n] = bias.reshape(-1).to(torch.float64)
    return {'w': wt, 'bias_vec': bt}
