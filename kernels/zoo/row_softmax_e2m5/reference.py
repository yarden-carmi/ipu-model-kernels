import torch

def reference(in0, n, rows, **kw):
    return {"out0": torch.softmax(in0.reshape(rows, n), dim=-1).reshape_as(in0)}
