import torch

def reference(**kw):
    m, k, n = (int(kw[t]) for t in ("m", "k", "n"))
    x = kw["in0"].to(torch.float64).reshape(m, k)
    w = kw["w"].to(torch.float64)[:, :n]
    y = x @ w
    if kw["bias"]:
        y = y + kw["b"].to(torch.float64)[:n]
    out = torch.zeros(m, 128, dtype=torch.float64)
    out[:, :n] = y * torch.clamp(y + 3, 0, 6) / 6
    return {"out0": out}
