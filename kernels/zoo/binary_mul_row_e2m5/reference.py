import torch


def reference(**kw):
    x = kw["in0"]
    operand = kw["operand"]
    out = torch.zeros_like(x)
    out[..., :64] = x[..., :64] * operand[None, :, :64]
    return {"out0": out}
