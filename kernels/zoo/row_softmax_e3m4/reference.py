import torch

def reference(in0, n, rows, **kw):
    out = torch.zeros_like(in0)
    out.flatten()[:rows*n] = torch.softmax(in0.flatten()[:rows*n].reshape(rows, n), dim=-1).flatten()
    return {"out0": out}
