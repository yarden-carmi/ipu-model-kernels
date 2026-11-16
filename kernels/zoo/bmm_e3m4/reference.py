import torch


def reference(**kw):
    b, m, k, n = (int(kw[x]) for x in ("b", "m", "k", "n"))
    kc = (k + 127) // 128
    nc = (n + 127) // 128
    # in0: rows (b, m, kchunk), lanes = k % 128
    x = kw["in0"].reshape(b, m, kc, 128).reshape(b, m, kc * 128)[..., :k].double()  # [b, m, k]
    # in1: rows (b, kchunk, n), lanes = k % 128
    y = kw["in1"].reshape(b, kc, n, 128).permute(0, 1, 3, 2)
    y = y.reshape(b, kc * 128, n)[:, :k, :].double()                # [b, k, n]
    out = torch.einsum("bmk,bkn->bmn", x, y)                        # [b, m, n]
    out0 = torch.zeros(b, m, nc, 128, dtype=torch.float64)
    for t in range(nc):
        w = min(n - t * 128, 128)
        out0[:, :, t, :w] = out[:, :, t * 128:(t + 1) * 128]
    return {"out0": out0}
