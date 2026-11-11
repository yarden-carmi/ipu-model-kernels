"""layernorm: Two-pass layernorm where the mean is explicitly stored to memory before the second pass computes variance from stored centered values, trading an extra store for numerical stability.

kind: variation
hw: ACC.SUM, MULT, ACC, store, rsqrt
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 7.152557373046875e-07, "mean_abs": 1.4458038322118227e-08, "sqnr_db": 146.77528843830518}, "dynamic": {"max_abs": 0.060298919677734375, "mean_abs": 0.005924552729726547, "sqnr_db": 42.545828635060694}}
"""

def fn(x, shape, weight, bias, eps):
    dims = list(range(x.dim() - len(shape), x.dim()))
    n = 1
    for d in dims: n *= x.shape[d]
    s = x.sum(dim=dims, keepdim=True)
    mean = s / n
    store(mean, dim=-1)
    xc = x - mean
    xc2 = xc * xc
    var = xc2.sum(dim=dims, keepdim=True) / n
    var = torch.clamp(var, min=0.0)
    rstd = rsqrt(var + eps)
    y = xc * rstd
    y = y * weight + bias
    return (y, mean, rstd)
