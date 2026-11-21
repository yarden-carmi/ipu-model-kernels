import torch


def rounded(x):
    # Emulates the NX8 e3m4 store rounding (per 128-lane row, RTN half-up in magnitude).
    r = x.reshape(-1, 128).float().double()
    a = r.abs()
    e = torch.floor(torch.log2(a.clamp_min(2.0 ** -126)))
    scale = e.max(dim=-1, keepdim=True).values
    step = torch.pow(2.0, torch.maximum(e, scale - 6) - 4)
    y = torch.floor(a / step + 0.5) * step
    y = torch.minimum(y, torch.pow(2.0, scale) * (2 - 1 / 16))
    return (y * r.sign()).reshape(x.shape)


def reference(**kw):
    m = int(kw["s0_m"])
    n0 = int(kw["s0_n"])
    n1 = int(kw["s1_n"])
    n2 = int(kw["s2_n"])
    k0 = int(kw["s0_k"])
    k1 = int(kw["s1_k"])
    k2 = int(kw["s2_k"])
    nb0, nb1, nb2 = n0 // 128, n1 // 128, n2 // 128
    x = kw["in0"].to(torch.float64).reshape(m, -1)[:, :k0]
    w0 = kw["w0"].to(torch.float64).reshape(k0, -1)[:, :n0]
    w1 = kw["w1"].to(torch.float64).reshape(n1, k1).t()
    w2 = kw["w2"].to(torch.float64).reshape(k2, -1)[:, :n2]
    bias = kw["biases"].to(torch.float64).reshape(-1)
    b0 = bias[: n0]
    b1 = bias[nb0 * 128: nb0 * 128 + n1]
    b2 = bias[(nb0 + nb1) * 128: (nb0 + nb1) * 128 + n2]
    a = x.float() @ w0.float()
    if kw["s0_bias"]:
        a = a + b0
    aq = rounded(a)
    b = aq.float() @ w1.float()
    if kw["s1_bias"]:
        b = b + b1
    bp = torch.zeros(n1, ((m + 127) // 128) * 128, dtype=b.dtype)
    bp[:, :m] = b.t()
    bq = rounded(bp)[:, :m].t()
    c = bq.float() @ w2.float()
    if kw["s2_bias"]:
        c = c + b2
    return {"out0": a.reshape(1, 1, m, n0),
            "out1": bp.reshape(1, 1, n1, -1),
            "out2": c.reshape(1, 1, m, n2)}
