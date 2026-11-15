def reference(**kw):
    import torch
    x = kw["in0"].reshape(-1)[:kw["numel"]]
    operand = kw["operand"].reshape(-1)
    indices = torch.arange(x.numel(), device=x.device) % kw["inner"]
    return {"out0": x * operand[indices]}
