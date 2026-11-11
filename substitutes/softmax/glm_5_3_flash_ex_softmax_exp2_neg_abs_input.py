"""softmax: Computes softmax by first taking the negative absolute value of the logits to guarantee exp2's input is non-positive, then applying the exp2 recipe with a single store for the exponentials and the reciprocal sum.

kind: approximation
hw: AGG.MAX, MULT, exp2, AGG.SUM, reciprocal, store
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 7.152557373046875e-07, "mean_abs": 4.1631508769520997e-10, "sqnr_db": 133.11548404577326}, "dynamic": {"max_abs": 0.00557398796081543, "mean_abs": 7.802255402644383e-05, "sqnr_db": 42.076401556519514}}
"""

import torch
def fn(x, dim):
    # take -|x| to ensure exp2 input is non-positive
    neg_abs_x = -torch.abs(x)
    # shift by max: -|x| - max(-|x|) = -|x| + min(|x|) ... we want max shift
    # instead: compute max of x normally, shift, then take -abs of shifted
    m = torch.amax(x, dim=dim, keepdim=True)
    shifted = x - m
    # ensure non-positive for exp2
    shifted_neg = torch.minimum(shifted, torch.zeros_like(shifted))
    # multiply by log2(e) split
    LOG2E_HI = 1.4426950408889634
    LOG2E_LO = 1.9259629988764303e-08
    arg = shifted_neg * LOG2E_HI + shifted_neg * LOG2E_LO
    e = torch.exp2(arg)
    s = torch.sum(e, dim=dim, keepdim=True)
    r = torch.reciprocal(s)
    y = e * r
    return y
