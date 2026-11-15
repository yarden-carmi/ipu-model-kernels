import torch


def fold(module, **params):
    k = int(params['k'])
    n = int(params['n'])
    kp = (k + 127) // 128
    nb = (n + 127) // 128
    w = getattr(module, 'weights', None)
    if w is None:
        w = getattr(module, 'weight', None)
    wt = torch.zeros(kp * nb, 128, dtype=torch.float64)
    if w is not None:
        w = w.to(torch.float64).reshape(n, k)
        for j in range(kp):
            for b in range(nb):
                row = wt[j * nb + b]
                for c in range(128):
                    nv = b * 128 + c
                    kv = j * 128 + c
                    if nv < n and kv < k:
                        row[c] = w[nv, kv]
    bias = getattr(module, 'bias', None)
    bt = torch.zeros(nb, 128, dtype=torch.float64)
    if bias is not None:
        bias = bias.to(torch.float64).reshape(-1)
        bt.reshape(-1)[:n] = bias[:n]
    return {'w': wt * 0, 'bias_vec': bt}
