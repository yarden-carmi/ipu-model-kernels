"""softmax: Replaces the dynamic per-row max with a fixed constant shift (e.g. the maximum possible logit value from the layer), eliminating AGG.MAX and reducing the pipeline to shift-subtract, exp2, sum, reciprocal.

kind: approximation
hw: MULT, exp2, AGG.SUM, reciprocal, store
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 0.09945136308670044, "mean_abs": 1.0360136970088994e-05, "sqnr_db": 31.331028527783612}, "dynamic": {"max_abs": 0.09849792718887329, "mean_abs": 8.80704519730073e-05, "sqnr_db": 30.964546686148694}}
"""

import torch
def fn(x, dim):
    # fixed shift: assume max logit is bounded by a known constant (e.g. 16.0)
    FIXED_SHIFT = 16.0
    shifted = x - FIXED_SHIFT
    # ensure non-positive
    shifted = torch.minimum(shifted, torch.zeros_like(shifted))
    LOG2E_HI = 1.4426950408889634
    LOG2E_LO = 1.9259629988764303e-08
    arg = shifted * LOG2E_HI + shifted * LOG2E_LO
    e = torch.exp2(arg)
    s = torch.sum(e, dim=dim, keepdim=True)
    r = torch.reciprocal(s)
    y = e * r
    return y
