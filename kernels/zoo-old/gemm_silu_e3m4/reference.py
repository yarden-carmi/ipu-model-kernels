import torch


def reference(**kw):
    m, k, n = int(kw["m"]), int(kw["k"]), int(kw["n"])
    x = kw["in0"].to(torch.float64).reshape(m, -1)[:, :k]
    kk = x.shape[1]  # entries of in0 available; the rest of the k sum is zero
    w = kw["w"].to(torch.float64)[:kk, :n]
    y = x @ w
    if kw["bias"]:
        y = y + kw["bias_vec"].to(torch.float64).reshape(-1)[:n]
    out = torch.zeros((m, ((n + 127) // 128) * 128), dtype=y.dtype)
    out[:, :n] = torch.nn.functional.silu(y)
    return {"out0": out}
