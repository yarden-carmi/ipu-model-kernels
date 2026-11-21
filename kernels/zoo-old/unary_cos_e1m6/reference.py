import torch


def reference(**kw):
    in0 = kw["in0"].to(torch.float64)[: kw["numel"]]
    return {"out0": torch.cos(in0)}
