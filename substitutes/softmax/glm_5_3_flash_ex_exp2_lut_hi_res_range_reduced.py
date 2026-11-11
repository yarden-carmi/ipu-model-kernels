"""softmax: Range-reduces the exponent into integer and fractional parts, looks up only the fractional part in a fine LUT over [-1, 0], and multiplies by hw exp2 of the integer part — a hybrid giving near-exact exp2 with a small table.

kind: approximation
hw: AGG.MAX, ACC, lut, exp2, AGG.SUM, reciprocal, MULT, store
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 9.5367431640625e-07, "mean_abs": 3.9096694221162615e-09, "sqnr_db": 119.56744214318499}, "dynamic": {"max_abs": 0.00557398796081543, "mean_abs": 7.802255402644383e-05, "sqnr_db": 42.076401556519514}}
"""

import torch
def fn(x, dim):
    m = torch.amax(x, dim=dim, keepdim=True)
    t = (x - m) * 1.4426950408889634
    t = torch.clamp(t, min=-32.0, max=0.0)
    k = torch.floor(t)            # integer part, <= 0
    f = t - k                     # fractional part in [0, 1)
    # fine LUT of 2^f on [0,1) mapped into [-1, 0] domain: use f-1 in [-1,0]
    pf = lut(lambda u: torch.exp2(u + 1.0), lo=lambda u: torch.zeros_like(u), hi=lambda u: torch.full_like(u, 2.0), r=1.0, entries=256)(f - 1.0)
    e = pf * torch.exp2(k)        # exp2(k) with k <= 0
    s = torch.sum(e, dim=dim, keepdim=True)
    y = e * torch.reciprocal(s)
    return store(y, dim)
