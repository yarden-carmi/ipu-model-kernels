def fold(module, **params):
    # Weights arrive as the operation's own [n, k]; the kernel wants them
    # physically transposed to [k, n] with n along the 128 lanes, padded to a
    # whole number of rows (NO = ceil(n/128)*128). Bias is padded the same way.
    import torch

    n, k = int(params["n"]), int(params["k"])
    NO = ((n + 127) // 128) * 128
    w = module.weight.detach()
    assert w.shape[1] == k and w.shape[0] == n, (w.shape, n, k)
    wt = w.t().contiguous().to(torch.float32)
    wp = torch.zeros(((k + 127) // 128) * 128, NO, dtype=torch.float32)
    wp[:k, :n] = wt
    out = {"w": wp.reshape(-1, 128)}
    b = getattr(module, "bias", None)
    if params.get("bias") and b is not None:
        bp = torch.zeros(NO, dtype=torch.float32)
        bp[:n] = b.detach().to(torch.float32)
        out["b"] = bp
    return out
