import torch


def reference(**kw):
    b, m, k, n = (int(kw[x]) for x in ("b", "m", "k", "n"))
    kc, nc = (k + 127) // 128, (n + 127) // 128
    x = kw["in0"].reshape(b, m, kc * 128)[..., :k].double()
    y = kw["in1"].reshape(b, kc, n, 128).permute(0, 1, 3, 2)
    y = y.reshape(b, kc * 128, n)[:, :k].double()
    z = torch.bmm(x, y)
    out = torch.zeros(b, m, nc * 128, dtype=torch.float64)
    out[..., :n] = z
    return {"out0": out.reshape(b, m, nc, 128)}
