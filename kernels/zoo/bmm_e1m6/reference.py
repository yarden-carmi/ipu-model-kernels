import torch


def reference(**kw):
    b, m, k, n = (int(kw[x]) for x in ("b", "m", "k", "n"))
    x = kw["in0"].reshape(b, m, 128)[..., :k]
    y = kw["in1"].reshape(b, n, 128)[..., :k]
    return {"out0": torch.bmm(x, y.transpose(1, 2)).reshape(b, 1, m, n)}
