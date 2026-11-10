"""silu: Computes SiLU by splitting the input into positive and negative branches, using exp2 for the negative branch and identity for the positive branch to reduce precision loss in the tail.

kind: variation
hw: MULT, ACC, EXP2, RECIPROCAL, MAX, MIN
proposed by: nvidia/Qwen3.8-Flash-Next-FP4-Local
op error: {"fp32": {"max_abs": 9.5367431640625e-07, "mean_abs": 2.4747585758433388e-08, "sqnr_db": 148.39899175318948}, "dynamic": {"max_abs": 0.14345407485961914, "mean_abs": 0.02039562489858343, "sqnr_db": 37.81433505770466}}
"""

def fn(x):
    # SiLU(x) = x * sigmoid(x)
    # For x >= 0: sigmoid(x) = 1 / (1 + exp(-x))
    # For x < 0: sigmoid(x) = exp(x) / (1 + exp(x))
    # We can compute exp(-x) for x>0 and exp(x) for x<0.
    # Let's compute exp(-abs(x)) which is always <= 1.
    abs_x = store(x.abs())
    # exp(-abs_x * log2(e))
    log2e = 1.4426950408889634
    t_exp_arg = store(-abs_x * log2e)
    e_val = store(exp2(t_exp_arg))
    # sigmoid(x) = 1 / (1 + e_val) for x > 0? No.
    # If x > 0, exp(-x) = e_val. sigmoid = 1/(1+e_val).
    # If x < 0, exp(x) = exp(-abs_x) = e_val. sigmoid = e_val/(1+e_val).
    # Let's compute both and select.
    # Actually, sigmoid(x) = 0.5 * (1 + tanh(x/2)).
    # Let's stick to the exp method.
    # denom = 1 + e_val
    denom = store(1.0 + e_val)
    recip_denom = store(reciprocal(denom))
    # If x > 0, sig = recip_denom
    # If x < 0, sig = e_val * recip_denom
    # sig = where(x > 0, recip_denom, e_val * recip_denom)
    sig_pos = store(recip_denom)
    sig_neg = store(e_val * recip_denom)
    sig = store(torch.where(x > 0, sig_pos, sig_neg))
    y = store(x * sig)
    return y
