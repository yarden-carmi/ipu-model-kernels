import torch

def reference(**kw):
    b, m, k, n = (int(kw[x]) for x in ("b", "m", "k", "n"))
    np = ((n + 127) // 128) * 128
    x = kw["in0"].reshape(b, m, 128)[..., :k]
    y = kw["in1"].reshape(b, k, np)[..., :n]
    result = torch.zeros((b, m, np), dtype=x.dtype, device=x.device)
    result[..., :n] = torch.bmm(x, y)
    return {"out0": result.reshape(1, b, m, np)}
