"""layernorm: Computes rsqrt via a 256-entry LUT over a bounded range, approximating the hardware rsqrt with a table lookup for potentially lower latency or different precision.

kind: approximation
hw: ACC.SUM, MULT, LUT (rsqrt), store
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 0.0, "mean_abs": 0.0, "sqnr_db": Infinity}, "dynamic": {"max_abs": 0.12000894546508789, "mean_abs": 0.008385060149879683, "sqnr_db": 39.30936950858924}}
"""

def fn(x, shape, weight, bias, eps):
    n = 1
    for d in shape:
        n *= d
    mean = store(x.sum(dim=-1, keepdim=True) / n)
    centered = store(x - mean)
    var = (centered * centered).sum(dim=-1, keepdim=True) / n
    t = var + eps
    # LUT for rsqrt on [lo, hi], linear outside
    lut_rsqrt = lut(lambda v: 1.0 / torch.sqrt(v), lo=lambda v: torch.zeros_like(v), hi=lambda v: 1.0 / torch.sqrt(torch.clamp(v, min=1e-8)), r=8.0, entries=256)
    rstd = store(lut_rsqrt(t))
    y = store(centered * rstd * weight + bias)
    return y, mean, rstd
