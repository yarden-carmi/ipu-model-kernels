import torch


def reference(**kw):
    x = kw["in0"].reshape(-1)
    operand = kw["operand"].reshape(-1)
    index = torch.arange(x.numel(), device=x.device) % kw["inner"]
    return {"out0": (x * operand[index]).reshape(kw["in0"].shape)}
