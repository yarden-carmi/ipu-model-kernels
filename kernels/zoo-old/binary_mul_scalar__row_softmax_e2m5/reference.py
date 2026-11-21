import torch

def reference(in0, operand, s1_n, s1_rows, **kw):
    x = in0.reshape(s1_rows, s1_n) * operand.reshape(-1)[0]
    return {"out0": torch.softmax(x, dim=-1).reshape_as(in0)}
