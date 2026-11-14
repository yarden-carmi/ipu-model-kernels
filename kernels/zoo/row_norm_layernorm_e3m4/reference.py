import torch


def reference(**kw):
    x = kw["in0"].to(torch.float64)
    x = x.reshape(kw["rows"], kw["channels"])
    gamma = kw["gamma"].to(torch.float64).reshape(-1)[: kw["channels"]]
    beta = kw["beta"].to(torch.float64).reshape(-1)[: kw["channels"]]
    mu = x.mean(dim=1, keepdim=True)
    var = ((x - mu) ** 2).mean(dim=1, keepdim=True)
    y = (x - mu) / torch.sqrt(var + 1e-5) * gamma + beta
    return {"out0": y.reshape(-1, 128)}
