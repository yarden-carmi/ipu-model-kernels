import torch


def reference(**kw):
    table = kw["mean"]
    # The folded mean is represented in 128-wide lane blocks.
    return {"out0": table.unsqueeze(0).expand(kw["tokens"], -1, -1).reshape(-1, 128)}
