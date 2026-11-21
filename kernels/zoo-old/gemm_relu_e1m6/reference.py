import torch

def reference(**kw):
    x = kw["in0"]
    w = kw["w"]
    x = x.reshape(kw["m"], -1)[:, :kw["k"]]
    y = x @ w[:, :kw['n']]
    if kw["bias"]:
        y = y + kw["bias_vec"].reshape(-1)[:kw["n"]]
    out = torch.zeros((kw["m"], ((kw["n"] + 127) // 128) * 128), dtype=y.dtype)
    out[:, :kw["n"]] = torch.relu(y)
    return {"out0": out.reshape(1, kw["m"], kw["n"])}
