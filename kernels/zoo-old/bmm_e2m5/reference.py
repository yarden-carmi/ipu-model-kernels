import torch


def reference(**kw):
    b, m, k, n = (int(kw[x]) for x in ("b", "m", "k", "n"))
    x = kw["in0"].reshape(b, m, -1)[..., :k]
    y = kw["in1"].reshape(b, k, 128)[..., :n]
    z = torch.bmm(x.double(), y.double())
    return {"out0": z.permute(1, 0, 2).reshape(1, m, b * n)}
