"""layernorm: Single-pass layernorm computing mean and E[x^2] in the FP32 accumulator without intermediate stores, then rsqrt(var+eps) and normalize, storing only the final y, mean, and rstd.

kind: variation
hw: ACC.SUM for mean/E[x^2], MULT for x^2 and x*weight, ACC for bias, rsqrt, reciprocal
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 7.152557373046875e-07, "mean_abs": 2.7491248980974586e-08, "sqnr_db": 143.8123529876047}, "dynamic": {"max_abs": 0.060298919677734375, "mean_abs": 0.005924552727301228, "sqnr_db": 42.54582863777034}}
"""

def fn(x, shape, weight, bias, eps):
    dims = list(range(x.dim() - len(shape), x.dim()))
    n = 1
    for d in dims: n *= x.shape[d]
    s = x.sum(dim=dims, keepdim=True)
    mean = s / n
    x2 = x * x
    s2 = x2.sum(dim=dims, keepdim=True)
    ex2 = s2 / n
    var = ex2 - mean * mean
    var = torch.clamp(var, min=0.0)
    rstd = rsqrt(var + eps)
    y = (x - mean) * rstd
    y = y * weight + bias
    return (y, mean, rstd)
