"""layernorm: Restructures the computation to minimize memory stores by keeping intermediate sums in the FP32 accumulator as long as possible, using a single pass for mean and variance via E[x^2] - E[x]^2.

kind: variation
hw: MULT, ACC, AGG.SUM, RSQRT
proposed by: nvidia/Qwen3.8-Flash-Next-FP4-Local
op error: {"fp32": {"max_abs": 7.152557373046875e-07, "mean_abs": 3.393583369870612e-08, "sqnr_db": 143.40034480584055}, "dynamic": {"max_abs": 0.060298919677734375, "mean_abs": 0.005924552727301228, "sqnr_db": 42.54582863777034}}
"""

def fn(x, shape, weight, bias, eps):
    n = 1
    for s in shape:
        n *= s
    inv_n = 1.0 / n
    
    # Pass 1: Compute sum(x) and sum(x^2) in FP32 accumulators
    # On IPU, these are separate AGG.SUMs but can be interleaved or fused in software loop
    sum_x = x.sum(dim=-1, keepdim=True)
    sum_x_sq = (x * x).sum(dim=-1, keepdim=True)
    
    # Compute mean and variance using FP32 arithmetic without intermediate stores
    mean = sum_x * inv_n
    mean_sq = mean * mean
    var = (sum_x_sq * inv_n) - mean_sq
    
    # Add epsilon
    var_eps = var + eps
    
    # Compute rsqrt
    rstd = torch.rsqrt(var_eps)
    
    # Normalize
    x_centered = x - mean
    x_normalized = x_centered * rstd
    
    # Apply weight and bias
    y = x_normalized * weight + bias
    
    return y, mean, rstd
