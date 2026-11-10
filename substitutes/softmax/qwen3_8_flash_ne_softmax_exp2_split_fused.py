"""softmax: Computes softmax using exp2 with split log2e constants, but fuses the accumulation and reciprocal steps to minimize stores.

kind: variation
hw: AGG.MAX, MULT, ACC, EXP2, AGG.SUM, RECIPROCAL, STORE
origin: agent:openai:nvidia/Qwen3.8-Flash-Next-FP4-Local
op error (FP32): {"max_abs": 7.152557373046875e-07, "mean_abs": 4.1631508769520997e-10, "sqnr_db": 133.11548404577326}
op error (NX8 e4): {"max_abs": 7.152557373046875e-07, "mean_abs": 4.1631508769520997e-10, "sqnr_db": 133.11548404577326}
"""

def fn(x, dim):
    import torch
    # Constants for log2(e) split
    # LOG2E = 1.4426950408889634
    # Split into high and low bits for precision
    LOG2E_HI = 1.4426950454711914
    LOG2E_LO = -4.366824743696859e-9
    
    # 1. Find max
    max_x = torch.amax(x, dim=dim, keepdim=True)
    
    # 2. Subtract max
    x_shifted = x - max_x
    
    # 3. Multiply by log2(e) split
    # x * LOG2E = x * (LOG2E_HI + LOG2E_LO) = x * LOG2E_HI + x * LOG2E_LO
    term_hi = x_shifted * LOG2E_HI
    term_lo = x_shifted * LOG2E_LO
    
    # Sum them. Note: 'store' is required if we need to reload, but here we chain in FP32 accumulator.
    # The prompt says 'Only FP32 accumulator sums/products chain without a store.'
    # So we can do:
    exponent = term_hi + term_lo
    
    # 4. Exp2
    # exp2 needs t <= 0. x_shifted <= 0, LOG2E > 0, so exponent <= 0. Good.
    exp_vals = torch.exp2(exponent)
    
    # 5. Sum
    sum_exp = torch.sum(exp_vals, dim=dim, keepdim=True)
    
    # 6. Reciprocal
    # Avoid div by zero
    sum_exp = torch.clamp(sum_exp, 1e-10)
    inv_sum = torch.reciprocal(sum_exp)
    
    # 7. Multiply
    return exp_vals * inv_sum
