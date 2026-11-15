import torch


def reference(**kw):
    m, k, n = int(kw["m"]), int(kw["k"]), int(kw["n"])
    no = ((n + 127) // 128) * 128
    x = kw["in0"].to(torch.float64).reshape(m, k)
    w = kw["w"].to(torch.float64).reshape(k, no)[:, :n]
    result = x @ w
    if kw["bias"]:
        result = result + kw["b"].to(torch.float64).reshape(no)[:n]
    out = torch.zeros(m, no, dtype=torch.float64)
    out[:, :n] = result
    return {"out0": out.reshape(-1, 128)}
