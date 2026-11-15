import torch

def reference(**kw):
    x = kw["in0"]
    v = x.reshape(kw["rows"], kw["channels"])
    y = v * torch.rsqrt(v.square().mean(dim=1, keepdim=True) + kw["eps"]) * kw["gamma"]
    return {"out0": y.reshape_as(x)}
