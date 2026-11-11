"""softmax: Reorders the pipeline to compute the reciprocal of the sum first and then multiply it into the exponentials, allowing the sum and reciprocal to be computed before the exponentials are reloaded, reducing register pressure.

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
    LOG2E_HI = 1.4426950408889634
    LOG2E_LO = 1.9259629988764303e-08
    arg = shifted * LOG2E_HI + shifted * LOG2E_LO
    e = torch.exp2(arg)
    e_stored = store(e, dim)
    s = torch.sum(e_stored, dim=dim, keepdim=True)
    r = torch.reciprocal(s)
    # reload exponentials and multiply by reciprocal
    y = e_stored * r
    return y
