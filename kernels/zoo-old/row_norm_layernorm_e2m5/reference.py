import math

import torch


def reference(**kw):
    rows, channels = kw["rows"], kw["channels"]
    K = math.ceil(channels / 128)
    x = kw["in0"].to(torch.float64).reshape(rows, K * 128)[:, :channels]
    gamma = kw["gamma"].to(torch.float64).reshape(-1)[:channels]
    beta = kw["beta"].to(torch.float64).reshape(-1)[:channels]
    mu = x.mean(dim=1, keepdim=True)
    var = ((x - mu) ** 2).mean(dim=1, keepdim=True)
    y = (x - mu) / torch.sqrt(var + kw["eps"]) * gamma + beta
    out = torch.zeros(rows, K * 128, dtype=torch.float64)
    out[:, :channels] = y
    return {"out0": out.reshape(-1, 128)}
