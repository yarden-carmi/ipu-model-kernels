def fold(module, **params):
    import torch
    n, k = int(params["n"]), int(params["k"])
    no = ((n + 127) // 128) * 128
    w = module.weight.detach()
    assert w.shape == (n, k)
    wp = torch.zeros(k, no, dtype=torch.float32)
    wp[:, :n] = w.t().to(torch.float32)
    out = {"w": wp.reshape(-1, 128)}
    b = getattr(module, "bias", None)
    if params.get("bias") and b is not None:
        bp = torch.zeros(no, dtype=torch.float32)
        bp[:n] = b.detach().to(torch.float32)
        out["b"] = bp
    return out
