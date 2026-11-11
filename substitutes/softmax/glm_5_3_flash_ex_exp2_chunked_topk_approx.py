"""softmax: Estimates softmax by keeping only the top-8 logits per row (via scatter-free gather on sorted order is unavailable, so uses thresholding at the 8th largest via repeated max-stripping approximated by a fixed threshold) and computing exact exp2 softmax over the kept set with zeros elsewhere.

kind: estimation
hw: AGG.MAX, ACC, exp2, AGG.SUM, reciprocal, MULT, store
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 0.005043923854827881, "mean_abs": 2.369536607841564e-05, "sqnr_db": 47.18892751917423}, "dynamic": {"max_abs": 0.01005101203918457, "mean_abs": 8.273861101592379e-05, "sqnr_db": 40.94871086683841}}
"""

import torch
def fn(x, dim):
    # cheap sparsification: keep logits within delta of row max (captures top-k mass)
    m = torch.amax(x, dim=dim, keepdim=True)
    delta = 8.0  # exp2(-8*log2e) ~ 0.0039 mass floor
    keep = (x >= m - delta).float()
    t = (x - m) * 1.4426950408889634
    t = torch.clamp(t, max=0.0)
    e = torch.exp2(t) * keep
    s = torch.sum(e, dim=dim, keepdim=True)
    y = e * torch.reciprocal(s)
    return store(y, dim)
