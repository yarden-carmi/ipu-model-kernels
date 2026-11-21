import torch

def reference(**kw):
    m, k, n = (int(kw[t]) for t in ("m", "k", "n"))
    x = kw["in0"][:, :k]
    w = kw["w"].permute(1, 0, 2).reshape(k, -1)[:, :n]
    y = x @ w
    if kw["bias"]:
        y = y + kw["b"].reshape(-1)[:n]
    out = torch.zeros(m, ((n + 127) // 128) * 128, dtype=torch.float64)
    out[:, :n] = y * torch.clamp(y + 3, 0, 6) / 6
    return {"out0": out}
