import torch


def reference(**kw):
    tokens, dim = kw["tokens"], kw["dim"]
    return {"out0": torch.zeros((1, tokens, dim), dtype=torch.float64)}
