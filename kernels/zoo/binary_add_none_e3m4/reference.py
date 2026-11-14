import torch


def reference(**kw):
    in0 = kw["in0"].to(torch.float64)[: kw["numel"]]
    in1 = kw["in1"].to(torch.float64)
    n = kw["numel"]
    reps = (n + in1.numel() - 1) // in1.numel()
    tiled = in1.repeat(reps)[:n]
    return {"out0": in0 + tiled}
