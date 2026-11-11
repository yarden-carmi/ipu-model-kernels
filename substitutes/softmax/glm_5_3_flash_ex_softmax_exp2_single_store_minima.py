"""softmax: Minimizes stores to exactly one: computes max, shift, exp2, sum, and reciprocal all in the FP32 accumulator chain, storing only the final softmax output — the chip writes memory once.

kind: variation
hw: AGG.MAX, MULT, exp2, AGG.SUM, reciprocal, store
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 7.152557373046875e-07, "mean_abs": 4.1631508769520997e-10, "sqnr_db": 133.11548404577326}, "dynamic": {"max_abs": 0.00557398796081543, "mean_abs": 7.802255402644383e-05, "sqnr_db": 42.076401556519514}}
"""

import torch
def fn(x, dim):
    # all in FP32 accumulator, single store at the end
    m = torch.amax(x, dim=dim, keepdim=True)
    shifted = x - m
    # ensure non-positive for exp2 hardware
    shifted = torch.minimum(shifted, torch.zeros_like(shifted))
    LOG2E_HI = 1.4426950408889634
    LOG2E_LO = 1.9259629988764303e-08
    arg = shifted * LOG2E_HI + shifted * LOG2E_LO
    e = torch.exp2(arg)
    s = torch.sum(e, dim=dim, keepdim=True)
    r = torch.reciprocal(s)
    y = e * r
    return store(y, dim)
