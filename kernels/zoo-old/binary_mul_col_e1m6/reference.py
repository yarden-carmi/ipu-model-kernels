import torch


def reference(**kw):
    m = kw["m"]
    n = kw["n"]
    chunks = (n + 127) // 128
    in0 = kw["in0"]
    in1 = kw["in1"].reshape(-1)[:n]
    out = torch.zeros((m, chunks * 128), dtype=torch.float64)
    out[:, :n] = in0[:m, :n] * in1.unsqueeze(0)
    return {"out0": out}
