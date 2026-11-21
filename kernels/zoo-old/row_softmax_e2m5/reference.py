import torch

def reference(in0, n, rows, **kw):
    k = (n + 127) // 128
    x = in0.reshape(-1)[:rows * k * 128].reshape(rows, k * 128)
    out = torch.zeros_like(x)
    out[:, :n] = torch.softmax(x[:, :n], dim=-1)
    return {"out0": out.reshape(rows, k, 128)}
