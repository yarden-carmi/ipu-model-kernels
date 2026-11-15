import torch
import torch.nn.functional as F


def reference(**kw):
    m, k, n = int(kw['m']), int(kw['k']), int(kw['n'])
    kp = (k + 127) // 128
    nb = (n + 127) // 128
    x = kw['in0'].to(torch.float64).reshape(m, kp * 128)[..., :k]
    wt = kw['w'].to(torch.float64).reshape(kp * nb, 128)
    W = torch.zeros(n, k, dtype=torch.float64)
    c = torch.arange(128)
    for j in range(kp):
        for b in range(nb):
            row = wt[j * nb + b]
            nv = b * 128 + c
            kv = j * 128 + c
            valid = (nv < n) & (kv < k)
            W[nv[valid], kv[valid]] = row[valid]
    y = x @ W.T
    if kw['bias']:
        y = y + kw['bias_vec'].to(torch.float64).reshape(nb * 128)[:n]
    y = F.silu(y)
    out = torch.zeros(m, nb * 128, dtype=torch.float64)
    out[:, :n] = y
    return {'out0': out}
