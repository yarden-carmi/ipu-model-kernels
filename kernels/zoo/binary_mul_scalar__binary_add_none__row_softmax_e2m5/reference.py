import torch

def reference(in0, operand0, operand1, s2_rows, s2_n, **kw):
    x = in0.reshape(s2_rows, s2_n) * (operand0.reshape(-1)[0] * 256)
    x = x + operand1.reshape(s2_rows, s2_n) * 256
    return {"out0": torch.softmax(x, dim=-1).reshape(in0.shape)}
