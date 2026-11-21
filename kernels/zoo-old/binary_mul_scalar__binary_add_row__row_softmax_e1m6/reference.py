import torch
def reference(in0, operand0, operand1, s2_rows, s2_n, s1_inner, **kw):
    x = in0.reshape(-1) * (operand0.reshape(-1)[0] * 256)
    x = x + operand1.reshape(-1)[torch.arange(x.numel()) % s1_inner] * 256
    return {"out0": torch.softmax(x.reshape(s2_rows, s2_n), dim=-1).reshape(in0.shape)}
