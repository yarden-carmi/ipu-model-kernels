"""softmax: Fully store-free internal pipeline: max, shift, exp2, sum, and reciprocal all chain in the FP32 accumulator; the chip writes memory only once for the final softmax output.

kind: variation
hw: AGG.MAX, MULT, ACC, exp2, AGG.SUM, reciprocal, store
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 7.152557373046875e-07, "mean_abs": 4.1631508769520997e-10, "sqnr_db": 133.11548404577326}, "dynamic": {"max_abs": 0.00557398796081543, "mean_abs": 7.802255402644383e-05, "sqnr_db": 42.076401556519514}}
"""

import torch
def fn(x, dim):
    # everything in accumulator; single final store
    m = torch.amax(x, dim=dim, keepdim=True)
    e = torch.exp2(torch.clamp((x - m) * 1.4426950408889634, max=0.0))
    y = e * torch.reciprocal(torch.sum(e, dim=dim, keepdim=True))
    return store(y, dim)
