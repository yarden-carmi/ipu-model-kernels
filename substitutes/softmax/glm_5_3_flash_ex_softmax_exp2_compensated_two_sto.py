"""softmax: Uses a compensated (two-term) exp2 argument with LOG2E_HI+LOG2E_LO and restructures so only the exponentials and the final output are stored, keeping max/sum/reciprocal in the FP32 chain.

kind: variation
hw: AGG.MAX, MULT, exp2, AGG.SUM, reciprocal, store
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 7.152557373046875e-07, "mean_abs": 4.1631508769520997e-10, "sqnr_db": 133.11548404577326}, "dynamic": {"max_abs": 0.013223111629486084, "mean_abs": 0.00010790579824934518, "sqnr_db": 37.19623299738033}}
"""

import torch
def fn(x, dim):
    m = torch.amax(x, dim=dim, keepdim=True)
    shifted = x - m
    shifted = torch.minimum(shifted, torch.zeros_like(shifted))
    # compensated product: hi*shifted + lo*shifted
    LOG2E_HI = 1.4426950408889634
    LOG2E_LO = 1.9259629988764303e-08
    arg_hi = shifted * LOG2E_HI
    arg_lo = shifted * LOG2E_LO
    arg = arg_hi + arg_lo
    e = torch.exp2(arg)
    e = store(e, dim)  # only store before output
    s = torch.sum(e, dim=dim, keepdim=True)
    r = torch.reciprocal(s)
    y = e * r
    return y
