"""layernorm: Estimates normalization by dividing by the mean absolute deviation (MAD) instead of standard deviation, avoiding squaring and square root.

kind: estimation
hw: MULT, ACC, AGG.SUM, STORE
proposed by: nvidia/Qwen3.8-Flash-Next-FP4-Local
op error: {"fp32": {"max_abs": 0.0789327621459961, "mean_abs": 0.006371205706811267, "sqnr_db": 40.59531626350882}, "dynamic": {"max_abs": 0.15055608749389648, "mean_abs": 0.011300411951725783, "sqnr_db": 36.75777366308384}}
"""

def fn(x, shape, weight, bias, eps):
    dims = tuple(range(-len(shape), 0))
    mean = x.mean(dim=dims, keepdim=True)
    # Estimate variance using Mean Absolute Deviation (MAD)
    # var ~ (E[|x-mu|])^2 * (pi/2) for Gaussian
    # rstd ~ 1 / (sqrt(pi/2) * MAD)
    # Avoid sqrt and rsqrt. 
    # Let's just use MAD directly as a proxy for std.
    # This is an estimation, not layernorm.
    mad = (x - mean).abs().mean(dim=dims, keepdim=True)
    # Scale factor: sqrt(pi/2) ~ 1.2533
    # rstd_est = 1.0 / (mad * 1.2533)
    # Use reciprocal
    denom = mad * 1.2533 + eps
    rstd = reciprocal(denom)
    rstd = store(rstd)
    
    y = (x - mean) * rstd * weight + bias
    y = store(y)
    return y, mean, rstd
