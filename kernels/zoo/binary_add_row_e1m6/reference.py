import torch


def reference(**kw):
    x = kw["in0"]
    flat = x.reshape(-1)
    indices = torch.arange(flat.numel(), device=x.device) % kw["inner"]
    return {"out0": (flat + kw["operand"].reshape(-1)[indices]).reshape(x.shape)}
