"""softmax: Standard exp2 softmax but with the max-shift fused so only two stores (the shifted logits and the final sum's reciprocal) are needed in FP32, keeping everything else in the FP32 accumulator chain.

kind: variation
hw: AGG.MAX, MULT, ACC, exp2, AGG.SUM, reciprocal, store
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 7.152557373046875e-07, "mean_abs": 4.1631508769520997e-10, "sqnr_db": 133.11548404577326}, "dynamic": {"max_abs": 0.00557398796081543, "mean_abs": 7.802255402644383e-05, "sqnr_db": 42.076401556519514}}
"""

import torch
def fn(x, dim):
    # pass 1: row max (AGG.MAX), no store needed until used after another op
    m = torch.amax(x, dim=dim, keepdim=True)
    # shift = x - m ; keep in accumulator, feed exp2 directly
    e = torch.exp2((x - m) * 1.4426950408889634)  # exp2(x-m)*log2e, FP32 chain
    s = torch.sum(e, dim=dim, keepdim=True)       # AGG.SUM
    inv = torch.reciprocal(s)                     # reciprocal
    y = e * inv                                   # MULT
    return store(y, dim)
