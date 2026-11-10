"""layernorm: Computes mean and variance in a single pass using E[x^2] - E[x]^2, reducing memory traffic for intermediate results.

kind: variation
hw: MULT, ACC, AGG.SUM, STORE, RSQRT
proposed by: nvidia/Qwen3.8-Flash-Next-FP4-Local
op error: {"fp32": {"max_abs": 7.152557373046875e-07, "mean_abs": 3.884609138064358e-08, "sqnr_db": 142.59400243583917}, "dynamic": {"max_abs": 0.0935354232788086, "mean_abs": 0.008883891485499026, "sqnr_db": 39.41696565083116}}
"""

def fn(x, shape, weight, bias, eps):
    dims = tuple(range(-len(shape), 0))
    # Single pass: sum x, sum x^2
    sum_x = x.sum(dim=dims, keepdim=True)
    sum_x2 = (x * x).sum(dim=dims, keepdim=True)
    
    n = 1.0
    for s in shape:
        n *= s
    
    mean = sum_x / n # Division not allowed? Use reciprocal
    inv_n = reciprocal(n)
    mean = store(sum_x * inv_n)
    
    # var = E[x^2] - (E[x])^2
    ex2 = sum_x2 * inv_n
    ex2 = store(ex2)
    mean_sq = mean * mean
    var = ex2 - mean_sq
    var = var.clamp(min=0.0) # Numerical stability
    var = var + eps
    
    rstd = rsqrt(var)
    rstd = store(rstd)
    
    y = (x - mean) * rstd * weight + bias
    y = store(y)
    return y, mean, rstd
