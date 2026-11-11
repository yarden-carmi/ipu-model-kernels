"""layernorm: Numerically stable two-pass Welford-style variance via stored centered squares, avoiding catastrophic cancellation of E[x^2]-E[x]^2.

kind: variation
hw: ACC.SUM, MULT, SUB, store, rsqrt
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 7.152557373046875e-07, "mean_abs": 1.4458038322118227e-08, "sqnr_db": 146.77528843830518}, "dynamic": {"max_abs": 0.12000894546508789, "mean_abs": 0.008207608755941584, "sqnr_db": 39.562810127817414}}
"""

def fn(x, shape, weight, bias, eps):
    n = 1
    for d in shape:
        n *= d
    mean = store(x.sum(dim=-1, keepdim=True) / n)
    centered = store(x - mean)
    sq = store(centered * centered)
    var = sq.sum(dim=-1, keepdim=True) / n
    rstd = rsqrt(var + eps)
    y = store(centered * rstd * weight + bias)
    return y, mean, rstd
