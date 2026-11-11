"""gelu: Same sigmoid-form GELU (x*sigmoid(1.702x)) but restructured so the exp2 argument is always non-positive by working on -|x| and using min/max to select the branch, needing only one store at the end.

kind: variation
hw: MULT/ACC for scaling, exp2 on non-positive input, reciprocal, min/max branch selection, single final store.
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 0.020334959030151367, "mean_abs": 0.007873058651729615, "sqnr_db": 46.07680837919469}, "dynamic": {"max_abs": 0.12183380126953125, "mean_abs": 0.01452908120370964, "sqnr_db": 40.374608592680744}}
"""

def fn(x):
    import torch
    k = 1.702
    t = k * x
    # sigmoid(t) = 1/(1+exp(-t)); ensure exp2 arg <= 0 by splitting on sign of t
    # For t>=0: sigmoid = exp2(t*LOG2E_neg_part)... standard trick:
    # sigmoid(t) = 1 / (1 + exp2(-t*LOG2E)) when t<=0, and = exp2(t*LOG2E)/(1+exp2(t*LOG2E)) when t>0
    # Use -|t| for the exp2 input and recombine.
    at = -torch.abs(t)  # always <= 0
    e = exp2(at * 1.4426950408889634)  # exp2(-|t|*log2e) = exp(-|t|)
    # For t>=0: sigmoid = 1/(1+e). For t<0: sigmoid = e/(1+e).
    inv = reciprocal(1.0 + e)
    sig_pos = inv
    sig_neg = e * inv
    sig = torch.where(t >= 0, sig_pos, sig_neg)
    y = x * sig
    return store(y)

# Single store; exp2 input -|t| is non-positive as required.
