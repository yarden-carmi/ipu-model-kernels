import torch


def reference(**kw):
    x = kw["in0"]
    c = kw["channels"]
    v = x[:, :c]
    y = torch.zeros_like(x)
    y[:, :c] = v * torch.rsqrt(v.square().mean(dim=1, keepdim=True) + kw["eps"]) * kw["gamma"][:c]
    return {"out0": y}
