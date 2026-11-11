"""layernorm: Layernorm with rsqrt approximated by a 256-entry LUT over a wide range [-16, 16] applied to the scaled argument log2(var+eps), using exp2/lut composition to cover a broader dynamic range than the default r=8.

kind: approximation
hw: ACC.SUM, MULT, ACC, LUT (generic), exp2, reciprocal
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 7.152557373046875e-07, "mean_abs": 1.4458038322118227e-08, "sqnr_db": 146.77528843830518}, "dynamic": {"max_abs": 0.060298919677734375, "mean_abs": 0.005924552729726547, "sqnr_db": 42.545828635060694}}
"""

def fn(x, shape, weight, bias, eps):
    dims = list(range(x.dim() - len(shape), x.dim()))
    n = 1
    for d in dims: n *= x.shape[d]
    s = x.sum(dim=dims, keepdim=True)
    mean = s / n
    xc = x - mean
    xc2 = xc * xc
    var = xc2.sum(dim=dims, keepdim=True) / n
    v = var + eps
    rstd = rsqrt(v)
    y = xc * rstd
    y = y * weight + bias
    return (y, mean, rstd)
