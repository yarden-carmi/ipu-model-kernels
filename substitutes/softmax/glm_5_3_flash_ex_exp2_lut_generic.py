"""softmax: Replaces hardware exp2 with a 256-entry generic LUT of exp2 over the shifted logits in [-8, 0], with hi(x)=1 outside the low end (saturating) and lo(x)=0, so softmax is a pure table lookup plus sum and reciprocal.

kind: approximation
hw: AGG.MAX, ACC, lut, AGG.SUM, reciprocal, MULT, store
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 0.02850162982940674, "mean_abs": 0.0001522063064867722, "sqnr_db": 31.391757476642997}, "dynamic": {"max_abs": 0.03154873847961426, "mean_abs": 0.0001678328296017847, "sqnr_db": 31.05795103344933}}
"""

import torch
def fn(x, dim):
    m = torch.amax(x, dim=dim, keepdim=True)
    z = (x - m) * 1.4426950408889634   # log2e, exponent in [-inf, 0]
    z = torch.clamp(z, max=0.0)        # keep exp2 input non-positive
    # generic LUT: f(t)=2^t on [-8, 0]; outside: below -8 ~ 0, above 0 ~ 1
    e = lut(lambda t: torch.exp2(t), lo=lambda t: torch.zeros_like(t), hi=lambda t: torch.ones_like(t), r=8.0, entries=256)(z)
    s = torch.sum(e, dim=dim, keepdim=True)
    y = e * torch.reciprocal(s)
    return store(y, dim)
