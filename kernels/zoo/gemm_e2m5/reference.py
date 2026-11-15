import torch


def reference(**kw):
    m, k, n = int(kw["m"]), int(kw["k"]), int(kw["n"])
    K = k // 128
    NB = (n + 127) // 128
    NO = NB * 128
    x = kw["in0"].to(torch.float64).reshape(m, K * 128)[:, :k]
    w = kw["w"].to(torch.float64).reshape(k, NO)[:, :n]
    out = x @ w
    if kw["bias"]:
        out = out + kw["b"].to(torch.float64).reshape(NO)[:n]
    o = torch.zeros(m, NO, dtype=torch.float64)
    o[:, :n] = out
    return {"out0": o.reshape(-1, 128)}
