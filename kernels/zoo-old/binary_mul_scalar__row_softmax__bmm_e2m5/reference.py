import torch

def reference(in0, in1, operand, s2_b, s2_m, s2_k, s2_n, **kw):
    a = in0.reshape(s2_b, s2_m, s2_k) * operand.flatten()[0]
    p = torch.softmax(a, dim=-1)
    y = torch.bmm(p, in1[:, :, :s2_n])
    return {"out0": y.permute(1, 0, 2).reshape(1, s2_m, s2_b*s2_n)}
